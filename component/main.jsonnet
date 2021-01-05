local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local rules = import 'rules.jsonnet';

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      annotations:: {},
      labels+: {
        'network.openshift.io/policy-group': 'monitoring',
      } + if std.member(inv.applications, 'networkpolicy') then {
        [inv.parameters.networkpolicy.labels.noDefaults]: 'true',
        [inv.parameters.networkpolicy.labels.purgeDefaults]: 'true',
      } else {},
    },
  },
  [if std.length(params.configs) > 0 then '10_configmap']:
    kube.ConfigMap('cluster-monitoring-config') {
      metadata+: {
        namespace: params.namespace,
      },
      data: {
        'config.yaml': std.manifestYamlDoc(
          std.mapWithKey(
            function(field, value) value + params.defaultConfig,
            params.configs
          )
        ),
      },
    },
  '10_alertmanager_config': kube.Secret('alertmanager-main') {
    metadata+: {
      namespace: params.namespace,
    },
    stringData: {
      'alertmanager.yaml': std.manifestYamlDoc(params.alertManagerConfig),
    },
  },
  prometheus_rules: rules,
}
