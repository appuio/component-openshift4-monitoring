local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local rl = import 'lib/resource-locker.libjsonnet';


local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local rules = import 'rules.jsonnet';
local capacity = import 'capacity.libsonnet';

local ns =
  if params.namespace != 'openshift-monitoring' then
    error 'Component openshift4-monitoring does not support values for parameter `namespace` other than "openshift-monitoring".'
  else
    params.namespace;

local ns_patch =
  rl.Patch(
    kube.Namespace(ns),
    {
      metadata: {
        labels: {
          'network.openshift.io/policy-group': 'monitoring',
        } + if std.member(inv.applications, 'networkpolicy') then {
          [inv.parameters.networkpolicy.labels.noDefaults]: 'true',
          [inv.parameters.networkpolicy.labels.purgeDefaults]: 'true',
        } else {},
      },
    }
  );

{
  '00_namespace_labels': ns_patch,
  [if std.length(params.configs) > 0 then '10_configmap']:
    kube.ConfigMap('cluster-monitoring-config') {
      metadata+: {
        namespace: ns,
      },
      data: {
        'config.yaml': std.manifestYamlDoc(
          {
            enableUserWorkload: params.enableUserWorkload,
          } + std.mapWithKey(
            function(field, value) value + params.defaultConfig,
            params.configs
          )
        ),
      },
    },
  [if params.enableUserWorkload then '10_configmap_user_workload']:
    kube.ConfigMap('user-workload-monitoring-config') {
      metadata+: {
        namespace: 'openshift-user-workload-monitoring',
      },
      data: {
        'config.yaml': std.manifestYamlDoc(
          std.mapWithKey(
            function(field, value) value + params.defaultConfig,
            params.configsUserWorkload
          )
        ),
      },
    },
  '10_alertmanager_config': kube.Secret('alertmanager-main') {
    metadata+: {
      namespace: ns,
    },
    stringData: {
      'alertmanager.yaml': std.manifestYamlDoc(params.alertManagerConfig),
    },
  },
  rbac: import 'rbac.libsonnet',
  prometheus_rules: rules,
  silence: import 'silence.jsonnet',
  [if params.capacityAlerts.enabled then 'capacity_rules']: capacity.rules,
} + {
  [group_name + '_rules']: prom.PrometheusRule(group_name) {
    metadata+: {
      namespace: params.namespace,
      labels+: {
        role: 'alert-rules',
      },
    },
    spec+: {
      groups+: [ {
        name: group_name,
        rules: [
          local rnamekey = std.splitLimit(rname, ':', 1);
          params.rules[group_name][rname] {
            [rnamekey[0]]: rnamekey[1],
            labels+: {
              syn: 'true',
            },
          }
          for rname in std.objectFields(params.rules[group_name])
          if params.rules[group_name][rname] != null
        ],
      } ],
    },
  }
  for group_name in std.objectFields(params.rules)
  if params.rules[group_name] != null
} + {
  '90_independent_monitoring': (import 'independent-monitoring.libsonnet'),
}
