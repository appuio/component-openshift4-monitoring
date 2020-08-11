local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;


{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      annotations:: {},
      labels+: {
        'network.openshift.io/policy-group': 'monitoring',
      } + if std.member(inv.classes, 'components.networkpolicy') then {
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
}
