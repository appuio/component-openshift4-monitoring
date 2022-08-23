local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local thanosMixinLib = import 'github.com/thanos-io/thanos/mixin/mixin.libsonnet';
local thanos = import 'kube-thanos/thanos.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local receiverCfg = {
  local this = self,
  name: 'thanos-receive',
  image: '%(registry)s/%(repository)s:%(tag)s' % params.images.thanos,
  version: params.images.thanos.tag,
  serviceMonitor: true,
  retention: '1d',
  objectStorageConfig: {
    name: this.name + '-objstorage',
    key: 'thanos.yaml',
  },
  resources: {
    requests: {
      cpu: '1',
      memory: '6Gi',
    },
    limits: {
      cpu: '4',
      memory: '10Gi',
    },
  },
  volumeClaimTemplate: {
    spec: {
      // Receiver only supports ReadWriteOnce
      accessModes: [ 'ReadWriteOnce' ],
      resources: {
        requests: {
          storage: '20Gi',
        },
      },
    },
  },
  // receiver doesn't actually use replica labels, but verifies that the field
  // is an array.
  replicaLabels: [],
  replicas: 1,
  replicationFactor: 1,
  // Clear security context to allow OCP4 to assign container UID
  securityContext: {},
} + com.makeMergeable(params.thanosRemoteWrite.receiver) + {
  // After adding user-supplied receiver config, render replica labels array
  // (remove labels prefixed with ~ and deduplicate labels).
  replicaLabels: com.renderArray(super.replicaLabels),
};
local thanosNs = receiverCfg.namespace;

local objStorageSecret =
  kube.Secret(receiverCfg.name + '-objstorage') {
    metadata+: {
      namespace: thanosNs,
    },
    stringData: {
      'thanos.yaml': std.manifestYamlDoc(
        params.thanosRemoteWrite.objectStorageConfig
      ),
    },
  };

local thanosReceiver = thanos.receive(receiverCfg);

local nsNodeSelector =
  std.join(
    ',',
    [
      '%s=%s' % [ k, params.defaultConfig.nodeSelector[k] ]
      for k in std.objectFields(params.defaultConfig.nodeSelector)
    ]
  );

local thanosMixin = thanosMixinLib {
  receive+:: {
    selector: 'job=~".*thanos-receive.*", namespace=~"%s"' % thanosNs,
  },
};
local alertlabels = {
  syn: 'true',
  syn_component: 'openshift4-monitoring',
};
local alertConfig = params.thanosRemoteWrite.receiverAlerts;
local rulePatch(rule) =
  local ruleConfig = com.getValueOrDefault(alertConfig, rule.alert, {});

  alertConfig['*'].patches +
  com.makeMergeable(com.getValueOrDefault(ruleConfig, 'patches', {}));

local ruleEnabled(rule) =
  local ruleConfig = com.getValueOrDefault(alertConfig, rule.alert, {});
  local globalEnabled = alertConfig['*'].enabled;
  com.getValueOrDefault(ruleConfig, 'enabled', globalEnabled);


local alerts =
  kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', receiverCfg.name) {
    metadata+: {
      namespace: thanosNs,
    },
    spec+: {
      groups: [
        group {
          rules: [
            rule {
              labels+: alertlabels,
            } + rulePatch(rule)
            for rule in super.rules
            if ruleEnabled(rule)
          ],
        }
        for group in thanosMixin.prometheusAlerts.groups
        if std.member([ 'thanos-receive', 'thanos-receive.rules' ], group.name)
      ],
    },
  };

local hasAlerts =
  local alertCount = std.foldl(
    function(sum, g) sum + std.length(g.rules),
    alerts.spec.groups,
    0
  );
  alertCount > 0;

{
  receiverURL: 'http://%s.%s.svc:19291/api/v1/receive' % [
    receiverCfg.name,
    receiverCfg.namespace,
  ],
  manifests: {
    [if thanosNs != params.namespace then '00_thanos_namespace']:
      kube.Namespace(thanosNs) {
        metadata+: {
          annotations: {
            'openshift.io/node-selector': nsNodeSelector,
          },
          labels: {
            'network.openshift.io/policy-group': 'monitoring',
            'openshift.io/cluster-monitoring': 'true',
          } + if std.member(inv.applications, 'networkpolicy') then {
            [inv.parameters.networkpolicy.labels.noDefaults]: 'true',
            [inv.parameters.networkpolicy.labels.purgeDefaults]: 'true',
          } else {},
        },
      },
    [if std.length(params.thanosRemoteWrite.objectStorageConfig) > 0 then '11_thanos_objstorage']:
      objStorageSecret,
    [if hasAlerts then '11_thanos_receiver_alerts']: alerts,
  } + {
    ['11_thanos_receiver_%s' % [ name ]]:
      if name == 'statefulSet' then
        thanosReceiver[name] {
          spec+: {
            template+: {
              spec+: {
                nodeSelector+: params.defaultConfig.nodeSelector,
              },
            },
          },
        }
      else
        thanosReceiver[name]
    for name in std.objectFields(thanosReceiver)
  },
}
