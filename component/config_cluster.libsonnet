// main template for openshift4-monitoring
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Configuration: Defaults

local _defaultsClusterMonitoring = com.makeMergeable({
  prometheusK8s: {
    remoteWrite: [],
    _remoteWrite: {},
    externalLabels: params.components.clusterMonitoring.externalLabels,
    retention: '8d',
    volumeClaimTemplate: {
      spec: {
        resources: {
          requests: {
            storage: '50Gi',
          },
        },
      },
    },
  },
  prometheusOperator: {},
  alertmanagerMain: {
    volumeClaimTemplate: {
      spec: {
        resources: {
          requests: {
            storage: '2Gi',
          },
        },
      },
    },
  },
  kubeStateMetrics: {},
  telemeterClient: {},
  openshiftStateMetrics: {},
  thanosQuerier: {},
  metricsServer: {},
  monitoringPlugin: {},
});

local _defaultsUserWorkload = com.makeMergeable({
  alertmanager: {
    enabled: true,
    enableAlertmanagerConfig: true,
    volumeClaimTemplate: {
      spec: {
        resources: {
          requests: {
            storage: '2Gi',
          },
        },
      },
    },
  },
  prometheusOperator: {},
  prometheus: {
    externalLabels: params.components.userWorkloadMonitoring.externalLabels,
    retention: '8d',
    volumeClaimTemplate: {
      spec: {
        resources: {
          requests: {
            storage: '50Gi',
          },
        },
      },
    },
  },
  thanosRuler: {},
});

// Configuration: Legacy

local _legacyClusterMonitoring = com.makeMergeable(
  if std.objectHas(params, 'configs') then
    std.trace('Parameter `configs` is deprecated, please use `components.clusterMonitoring.config`.', params.configs)
  else {},
);

local _legacyUserWorkload = com.makeMergeable(
  if std.objectHas(params, 'configsUserWorkload') then
    std.trace('Parameter `configsUserWorkload` is deprecated, please use `components.userWorkloadMonitoring.config`.', params.configsUserWorkload)
  else {},
);

local _legacyRemoteWriteClusterMonitoring = com.makeMergeable(
  local defaults = std.get(params, 'remoteWriteDefaults', { cluster: {} });
  if std.length(defaults.cluster) > 0 then
    std.trace('Parameter `remoteWriteDefaults.cluster` is deprecated, please use `components.clusterMonitoring.remoteWriteDefaults`.', defaults.cluster)
  else {},
);

local _legacyRemoteWriteUserWorkload = com.makeMergeable(
  local defaults = std.get(params, 'remoteWriteDefaults', { userWorkload: {} });
  if std.length(defaults.userWorkload) > 0 then
    std.trace('Parameter `remoteWriteDefaults.userWorkload` is deprecated, please use `components.userWorkloadMonitoring.remoteWriteDefaults`.', defaults.userWorkload)
  else {},
);

local _legacyDefaultConfig =
  if std.objectHas(params, 'defaultConfig') then
    std.trace('Parameter `defaultConfig` is deprecated, please use `components.clusterMonitoring.config` and `components.userWorkloadMonitoring.config`.', params.defaultConfig)
  else {
    nodeSelector: params.defaultNodeSelector,
  };

// Configuration: Final

local configClusterMonitoring = _defaultsClusterMonitoring + com.makeMergeable(params.components.clusterMonitoring.config) + _legacyClusterMonitoring;
local configUserWorkload = _defaultsUserWorkload + com.makeMergeable(params.components.userWorkloadMonitoring.config) + _legacyUserWorkload;

local remoteWriteDefaultsClusterMonitoring = com.makeMergeable(params.components.clusterMonitoring.remoteWriteDefaults) + _legacyRemoteWriteClusterMonitoring;
local remoteWriteDefaultsUserWorkload = com.makeMergeable(params.components.userWorkloadMonitoring.remoteWriteDefaults) + _legacyRemoteWriteUserWorkload;

local userWorkloadEnabled =
  if std.objectHas(params, 'enableUserWorkload') then
    std.trace('Parameter `enableUserWorkload` is deprecated, please use `components.userWorkloadMonitoring.enabled`.', params.enableUserWorkload)
  else
    params.components.userWorkloadMonitoring.enabled;

// Helpers: RemoteWrite

local transformRelabelConfigs(config) =
  if std.objectHas(config, 'writeRelabelConfigs') then
    config {
      writeRelabelConfigs: std.map(
        function(wrlc) wrlc {
          timeseries:: [],
          [if std.objectHas(wrlc, 'timeseries') && std.length(com.renderArray(wrlc.timeseries)) > 0
          then 'regex']: std.format('(%s)', std.join('|', com.renderArray(wrlc.timeseries))),
        },
        config.writeRelabelConfigs,
      ),
    }
  else config;

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

// Manifests

local clusterMonitoring = kube.ConfigMap('cluster-monitoring-config') {
  metadata+: {
    namespace: 'openshift-monitoring',
  },
  data: {
    'config.yaml': std.manifestYamlDoc(
      std.prune(
        {
          enableUserWorkload: userWorkloadEnabled,
        } + std.mapWithKey(
          function(field, value)
            if !std.member([ 'nodeExporter', 'prometheusOperatorAdmissionWebhook' ], field) then
              _legacyDefaultConfig + com.makeMergeable(value)
            else
              // fields `nodeExporter` and `prometheusOperatorAdmissionWebhook`
              // don't support field `nodeSelector` which we set in the
              // default config, so we don't apply the default config for
              // those fields.
              std.trace("Not applying default config for '%s'" % field, value),
          configClusterMonitoring {
            prometheusK8s: patchRemoteWrite(super.prometheusK8s, remoteWriteDefaultsClusterMonitoring),
          }
        ),
      )
    ),
  },
};

local userWorkload = kube.ConfigMap('user-workload-monitoring-config') {
  metadata+: {
    namespace: 'openshift-user-workload-monitoring',
  },
  data: {
    'config.yaml': std.manifestYamlDoc(
      std.mapWithKey(
        function(field, value) _legacyDefaultConfig + com.makeMergeable(value),
        configUserWorkload {
          prometheus: patchRemoteWrite(super.prometheus, remoteWriteDefaultsUserWorkload),
        }
      )
    ),
  },
};

// Define outputs below
{
  '20_config_cluster_monitoring': clusterMonitoring,
  [if userWorkloadEnabled then '20_config_user_workload']: userWorkload,
}
