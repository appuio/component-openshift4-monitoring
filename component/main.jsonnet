local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';
local prom = import 'lib/prom.libsonnet';


local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local rules = import 'rules.jsonnet';
local capacity = import 'capacity.libsonnet';

local alertDiscovery = import 'alert-routing-discovery.libsonnet';

local ns =
  if params.namespace != 'openshift-monitoring' then
    error 'Component openshift4-monitoring does not support values for parameter `namespace` other than "openshift-monitoring".'
  else
    params.namespace;

local secrets = com.generateResources(params.secrets, kube.Secret);

local ns_patch =
  po.Patch(
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

local transformRelabelConfigs(remoteWriteConfig) = if std.objectHas(remoteWriteConfig, 'writeRelabelConfigs')
then remoteWriteConfig {
  writeRelabelConfigs: std.map(
    function(wrlc) wrlc {
      timeseries:: [],
      [if std.objectHas(wrlc, 'timeseries') && std.length(com.renderArray(wrlc.timeseries)) > 0
      then 'regex']: std.format('(%s)', std.join('|', com.renderArray(wrlc.timeseries))),
    },
    remoteWriteConfig.writeRelabelConfigs,
  ),

}
else remoteWriteConfig;

local patchRemoteWrite(promConfig, defaults) = promConfig {
  _remoteWrite+:: {},
} + {
  local rwd = super._remoteWrite,
  remoteWrite+: std.filterMap(
    function(name) rwd[name] != null,
    function(name) transformRelabelConfigs(rwd[name] { name: name }),
    std.objectFields(rwd)
  ),
} + {
  remoteWrite: std.map(
    function(rw) defaults + com.makeMergeable(rw),
    super.remoteWrite,
  ),
};

local customRules =
  prom.generateRules('custom-rules', params.rules);

{
  '00_namespace_labels': ns_patch,
  '01_secrets': secrets,
  '02_aggregated_clusterroles': (import 'aggregated-clusterroles.libsonnet'),
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
            params.configs {
              prometheusK8s: patchRemoteWrite(super.prometheusK8s, params.remoteWriteDefaults.cluster),
            }
          ),
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
            params.configsUserWorkload {
              prometheus: patchRemoteWrite(super.prometheus, params.remoteWriteDefaults.userWorkload),
            }
          )
        ),
      },
    },
  '10_alertmanager_config': kube.Secret('alertmanager-main') {
    metadata+: {
      namespace: ns,
    },
    stringData: {
      'alertmanager.yaml': if params.alertManagerAutoDiscovery.enabled then std.manifestYamlDoc(alertDiscovery.alertmanagerConfig) else alertDiscovery.alertmanagerConfig,
    },
  },
  [if params.alertManagerAutoDiscovery.enabled && params.alertManagerAutoDiscovery.debug_config_map then '99_discovery_debug_cm']: alertDiscovery.debugConfigMap,

  [if params.enableAlertmanagerIsolationNetworkPolicy then '20_networkpolicy']: std.map(function(p) com.namespaced('openshift-monitoring', p), import 'networkpolicy.libsonnet'),
  [if params.enableUserWorkload && params.enableUserWorkloadAlertmanagerIsolationNetworkPolicy then '20_user_workload_networkpolicy']: std.map(function(p) com.namespaced('openshift-user-workload-monitoring', p), import 'networkpolicy.libsonnet'),
  rbac: import 'rbac.libsonnet',
  prometheus_rules: rules,
  silence: import 'silence.jsonnet',
  [if params.capacityAlerts.enabled then 'capacity_rules']: capacity.rules,
  [if std.length(customRules.spec.groups) > 0 then 'custom_rules']: customRules,
}
