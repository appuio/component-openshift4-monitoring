local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;
local facts = inv.facts;

local clusterMonitoringConfig = {
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
} + com.makeMergeable(params.components.clusterMonitoring.config);

local userWorkloadMonitoringConfig = {
  alertmanager: {
    enabled: true,
    enableAlertmanagerConfig: true,
    volumeClaimTemplate: clusterMonitoringConfig.alertmanagerMain.volumeClaimTemplate,
  },
  prometheusOperator: {},
  prometheus: {
    externalLabels: params.components.userWorkloadMonitoring.externalLabels,
    retention: '8d',
    volumeClaimTemplate: clusterMonitoringConfig.prometheusK8s.volumeClaimTemplate,
  },
  thanosRuler: {},
} + com.makeMergeable(params.components.userWorkloadMonitoring.config);

local customNodeExporter = {
  enabled: params.components.customNodeExporter.enabled,
  args: params.components.customNodeExporter.args,
  collectors: [ 'network_route' ] + params.components.customNodeExporter.collectors,
  metricRelabelings: [
    // only keep routes for host interfaces (assumes that host interfaces
    // are `ensX` which should hold on RHCOS)
    {
      action: 'keep',
      sourceLabels: [ '__name__', 'device' ],
      regex: 'node_network_route.*;ens.*',
    },
  ] + params.components.customNodeExporter.metricRelabelings,
};

local capacityAlerts = {
  enabled: params.components.capacityAlerts.enabled,
  groupByNodeLabels: params.components.capacityAlerts.groupByNodeLabels,
  groups: {
    PodCapacity: {
      rules: {
        TooManyPods: {
          enabled: true,
          annotations: {
            message: 'Only {{ $value }} more pods can be started.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/podcapacity.html#SYN_TooManyPods',
            description: 'The cluster is close to the limit of running pods. The cluster might not be able to handle node failures and might not be able to start new pods. Consider adding new nodes.',
          },
          'for': '30m',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
          },
        },
        ExpectTooManyPods: {
          enabled: false,
          annotations: {
            message: 'Expected to exceed the threshold of running pods in 3 days',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/podcapacity.html#SYN_ExpectTooManyPods',
            description: 'The cluster is getting close to the limit of running pods. Soon the cluster might not be able to handle node failures and might not be able to start new pods. Consider adding new nodes.',
          },
          'for': '3h',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
            // How much of the past to consider for the prediction
            range: '1d',
            // How far into the future to predict (in seconds)
            predict: '3*24*60*60',
          },
        },
      },
    },

    ResourceRequests: {
      rules: {
        TooMuchMemoryRequested: {
          enabled: true,
          annotations: {
            message: 'Only {{ $value }} memory left for new pods.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/resourcerequests.html#SYN_TooMuchMemoryRequested',
            description: 'The cluster is close to assigning all memory to running pods. The cluster might not be able to handle node failures and might not be able to start new pods. Consider adding new nodes.',
          },
          'for': '30m',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
          },
        },
        ExpectTooMuchMemoryRequested: {
          enabled: false,
          annotations: {
            message: 'Expected to exceed the threshold of requested memory in 3 days',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/resourcerequests.html#SYN_ExpectTooMuchMemoryRequested',
            description: 'The cluster is getting close to assigning all memory to running pods. Soon the cluster might not be able to handle node failures and might not be able to start new pods. Consider adding new nodes.',
          },
          'for': '3h',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
            // How much of the past to consider for the prediction
            range: '1d',
            // How far into the future to predict (in seconds)
            predict: '3*24*60*60',
          },
        },
        TooMuchCPURequested: {
          enabled: true,
          annotations: {
            message: 'Only {{ $value }} cpu cores left for new pods.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/resourcerequests.html#SYN_TooMuchCPURequested',
            description: 'The cluster is close to assigning all CPU resources to running pods. The cluster might not be able to handle node failures and might soon not be able to start new pods. Consider adding new nodes.',
          },
          'for': '30m',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
          },
        },
        ExpectTooMuchCPURequested: {
          enabled: false,
          annotations: {
            message: 'Expected to exceed the threshold of requested CPU resources in 3 days',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/resourcerequests.html#SYN_ExpectTooMuchCPURequested',
            description: 'The cluster is getting close to assigning all CPU cores to running pods. Soon the cluster might not be able to handle node failures and might not be able to start new pods. Consider adding new nodes.',
          },
          'for': '3h',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
            // How much of the past to consider for the prediction
            range: '1d',
            // How far into the future to predict (in seconds)
            predict: '3*24*60*60',
          },
        },
      },
    },

    MemoryCapacity: {
      rules: {
        ClusterLowOnMemory: {
          enabled: true,
          annotations: {
            message: 'Only {{ $value }} free memory on Worker Nodes.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/memorycapacity.html#SYN_ClusterMemoryUsageHigh',
            description: 'The cluster is close to using all of its memory. The cluster might not be able to handle node failures or load spikes. Consider adding new nodes.',
          },
          'for': '30m',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
          },
        },
        ExpectClusterLowOnMemory: {
          enabled: false,
          annotations: {
            message: 'Cluster expected to run low on memory in 3 days',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/memorycapacity.html#SYN_ExpectClusterMemoryUsageHigh',
            description: 'The cluster is getting close to using all of its memory. Soon the cluster might not be able to handle node failures or load spikes. Consider adding new nodes.',
          },
          'for': '3h',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
            // How much of the past to consider for the prediction
            range: '1d',
            // How far into the future to predict (in seconds)
            predict: '3*24*60*60',
          },
        },
      },
    },

    CpuCapacity: {
      rules: {
        ClusterCpuUsageHigh: {
          enabled: true,
          annotations: {
            message: 'Only {{ $value }} idle cpu cores accross cluster.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/cpucapacity.html#SYN_ClusterCpuUsageHigh',
            description: 'The cluster is close to using up all CPU resources. The cluster might not be able to handle node failures or load spikes. Consider adding new nodes.',
          },
          'for': '30m',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
          },
        },
        ExpectClusterCpuUsageHigh: {
          enabled: false,
          annotations: {
            message: 'Cluster expected to run low on available CPU resources in 3 days',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/cpucapacity.html#SYN_ExpectClusterCpuUsageHigh',
            description: 'The cluster is getting close to using up all CPU resources. The cluster might soon not be able to handle node failures or load spikes. Consider adding new nodes.',
          },
          'for': '3h',
          labels: {},
          expr: {
            // The alert specific threshold is multiplied by this factor. 1 == one node
            factor: 1,
            // How much of the past to consider for the prediction
            range: '1d',
            // How far into the future to predict (in seconds)
            predict: '3*24*60*60',
          },
        },
      },
    },

    UnusedCapacity: {
      rules: {
        ClusterHasUnusedNodes: {
          enabled: true,
          annotations: {
            message: 'Cluster has unused nodes.',
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/unusedcapacity.html#SYN_ClusterHasUnusedNodes',
            description: 'The cluster has {{ $value }} unused nodes. Consider removing unused nodes.',
          },
          'for': '8h',
          labels: {},
          expr: {
            // How many nodes need to be unused.
            // There should be some overcapacity to account for failing nodes and future growth.
            reserved: 4,
          },
        },
      },
    },
  } + com.makeMergeable({
    [key]: params.capacityAlerts[key]
    for key in std.objectFields(params.capacityAlerts)
    if !std.member([ 'enabled', 'groupByNodeLabels', 'groups' ], key)
  }),
};

local alerts = {
  includeNamespaces: [
    'appuio.*',
    'cilium',
    'default',
    'kube-.*',
    'openshift-.*',
    'syn.*',
  ],
  ignoreNames: [
    'AlertmanagerReceiversNotConfigured',
    'CannotRetrieveUpdates',
    'ClusterProxyApplySlow',
    'ConfigReloaderSidecarErrors',
    'FailingOperator',
    'GarbageCollectorSyncFailed',
    'ImageRegistryStorageReconfigured',
    'IngressWithoutClassName',
    'KubeCPUOvercommit',
    'KubeCPUQuotaOvercommit',
    'KubeHpaMaxedOut',
    'KubeHpaReplicasMismatch',
    'KubeMemoryOvercommit',
    'KubeMemoryQuotaOvercommit',
    'KubeQuotaExceeded',
    'KubeStateMetricsListErrors',
    'NodeRAIDDegraded',
    'NodeRAIDDiskFailure',
    'NodeSystemSaturation',
    'NodeTextFileCollectorScrapeError',
    'PrometheusOperatorListErrors',
    'PrometheusOperatorNodeLookupErrors',
    'SchedulerLegacyPolicySet',
    'TechPreviewNoUpgrade',
    'ThanosQueryGrpcClientErrorRate',
    'ThanosQueryGrpcServerErrorRate',
    'ThanosQueryHighDNSFailures',
    'ThanosRuleAlertmanagerHighDNSFailures',
    'ThanosRuleQueryHighDNSFailures',
    'node_cpu_load5',
  ],
  ignoreWarnings: [
    'ExtremelyHighIndividualControlPlaneCPU',
    'MachineConfigControllerPausedPoolKubeletCA',
    'NodeClockNotSynchronising',
    'NodeFileDescriptorLimit',
    'NodeFilesystemAlmostOutOfFiles',
    'NodeFilesystemAlmostOutOfSpace',
    'NodeFilesystemFilesFillingUp',
    'ThanosRuleRuleEvaluationLatencyHigh',
    'etcdDatabaseHighFragmentationRatio',
    'etcdExcessiveDatabaseGrowth',
    'etcdHighCommitDurations',
    'etcdHighFsyncDurations',
    'etcdHighNumberOfFailedGRPCRequests',
    'etcdMemberCommunicationSlow',
  ],
  ignoreGroups: [
    'CloudCredentialOperator',
    'SamplesOperator',
    'kube-apiserver-slos-basic',
  ],
  patchRules: {
    // rules patched in '*' will be applied regardless of the value of
    // parameter `manifests_version`.
    '*': {
      HighOverallControlPlaneMemory: {
        annotations: {
          description: |||
            The overall memory usage is high.
            kube-apiserver and etcd might be slow to respond.
            To fix this, increase memory of the control plane nodes.

            This alert was adjusted to be less sensitive in 4.11.
            Newer Go versions use more memory, if available, to reduce GC pauses.

            Old memory behavior can be restored by setting `GOGC=63`.
            See https://bugzilla.redhat.com/show_bug.cgi?id=2074031 for more details.
          |||,
        },
        expr: |||
          (
            1
            -
            sum (
              node_memory_MemFree_bytes
              + node_memory_Buffers_bytes
              + node_memory_Cached_bytes
              AND on (instance)
              label_replace( kube_node_role{role="master"}, "instance", "$1", "node", "(.+)" )
            ) / sum (
              node_memory_MemTotal_bytes
              AND on (instance)
              label_replace( kube_node_role{role="master"}, "instance", "$1", "node", "(.+)" )
            )
          ) * 100 > 80
        |||,
      },
      PrometheusRemoteWriteBehind: {
        annotations: {
          runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/remotewrite.html',
        },
      },
      PrometheusRemoteWriteDesiredShards: {
        annotations: {
          runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/remotewrite.html',
        },
      },
      NodeMemoryMajorPagesFaults: {
        // Only alert for >100*cores major page faults/node instead of >500/node
        expr: 'rate(node_vmstat_pgmajfault{job="node-exporter"}[5m]) > on (instance) (count by (instance) (node_cpu_info{}) * 100)',
      },
    },
  },
} + com.makeMergeable(params.alerts);

local alertManagerConfig = {
  route: {
    group_wait: '0s',
    group_interval: '5s',
    repeat_interval: '10m',
  },
  inhibit_rules: [
    // Don't send warning or info if a critical is already firing
    {
      target_match_re: {
        severity: 'warning|info',
      },
      source_match: {
        severity: 'critical',
      },
      equal: [
        'namespace',
        'alertname',
      ],
    },
    // Don't send info if a warning is already firing
    {
      target_match_re: {
        severity: 'info',
      },
      source_match: {
        severity: 'warning',
      },
      equal: [
        'namespace',
        'alertname',
      ],
    },
  ],
} + com.makeMergeable(params.components.alertManager.config);

local alertManagerAutoDiscovery = {
  enabled: params.components.alertManagerAutoDiscovery.enabled,
  debug_config_map: params.components.alertManagerAutoDiscovery.debugConfigMap,
  team_receiver_format: params.components.alertManagerAutoDiscovery.teamReceiverFormat,
  additional_alert_matchers: params.components.alertManagerAutoDiscovery.additionalAlertMatchers,
  prepend_routes: params.components.alertManagerAutoDiscovery.prependRoutes,
  append_routes: params.components.alertManagerAutoDiscovery.appendRoutes,
};

local silence = {
  schedule: '0 */4 * * *',
  serviceAccountName: 'prometheus-k8s',
  servingCertsCABundleName: 'serving-certs-ca-bundle',
  jobHistoryLimit: {
    failed: 3,
    successful: 3,
  },
  nodeSelector: params.defaultNodeSelector,
  silences: {
    'Silence non syn alerts': {
      matchers: [
        {
          name: 'alertname',
          value: '.+',
          isRegex: true,
        },
        {
          name: 'syn',
          value: '',
          isRegex: false,
        },
      ],
    },
  },
} + com.makeMergeable(params.silence);

// Define exports below
{
  enableUserWorkload:
    if std.objectHas(params, 'enableUserWorkload') then
      std.trace('Parameter `enableUserWorkload` is deprecated, please use `components.userWorkloadMonitoring.enabled`.', params.enableUserWorkload)
    else
      params.components.userWorkloadMonitoring.enabled,

  enableAlertmanagerIsolationNetworkPolicy:
    if std.objectHas(params, 'enableAlertmanagerIsolationNetworkPolicy') then
      std.trace('Parameter `enableAlertmanagerIsolationNetworkPolicy` is deprecated, please use `components.clusterMonitoring.alertmanagerIsolationEnabled`.', params.enableAlertmanagerIsolationNetworkPolicy)
    else
      params.components.clusterMonitoring.alertmanagerIsolationEnabled,
  enableUserWorkloadAlertmanagerIsolationNetworkPolicy:
    if std.objectHas(params, 'enableUserWorkloadAlertmanagerIsolationNetworkPolicy') then
      std.trace('Parameter `enableUserWorkloadAlertmanagerIsolationNetworkPolicy` is deprecated, please use `components.userWorkloadMonitoring.alertmanagerIsolationEnabled`.', params.enableUserWorkloadAlertmanagerIsolationNetworkPolicy)
    else
      params.components.userWorkloadMonitoring.alertmanagerIsolationEnabled,

  configs: clusterMonitoringConfig + com.makeMergeable(
    if std.objectHas(params, 'configs') then
      std.trace('Parameter `configs` is deprecated, please use `components.clusterMonitoring.config`.', params.configs)
    else {},
  ),
  configsUserWorkload: userWorkloadMonitoringConfig + com.makeMergeable(
    if std.objectHas(params, 'configsUserWorkload') then
      std.trace('Parameter `configsUserWorkload` is deprecated, please use `components.userWorkloadMonitoring.config`.', params.configsUserWorkload)
    else {},
  ),

  remoteWriteDefaults: {
    cluster: params.components.clusterMonitoring.remoteWriteDefaults + com.makeMergeable(
      local defaults = std.get(params, 'remoteWriteDefaults', { cluster: {} });
      if std.length(defaults.cluster) > 0 then
        std.trace('Parameter `remoteWriteDefaults.cluster` is deprecated, please use `components.clusterMonitoring.remoteWriteDefaults`.', defaults.cluster)
      else {},
    ),
    userWorkload: params.components.userWorkloadMonitoring.remoteWriteDefaults + com.makeMergeable(
      local defaults = std.get(params, 'remoteWriteDefaults', { userWorkload: {} });
      if std.length(defaults.userWorkload) > 0 then
        std.trace('Parameter `remoteWriteDefaults.userWorkload` is deprecated, please use `components.userWorkloadMonitoring.remoteWriteDefaults`.', defaults.userWorkload)
      else {},
    ),
  },

  defaultConfig:
    if std.objectHas(params, 'defaultConfig') then
      std.trace('Parameter `defaultConfig` is deprecated, please use `components.clusterMonitoring.config` and `components.userWorkloadMonitoring.config`.', params.defaultConfig)
    else {
      nodeSelector: params.defaultNodeSelector,
    },

  customNodeExporter: customNodeExporter + com.makeMergeable(
    if std.objectHas(params, 'customNodeExporter') then
      std.trace('Parameter `customNodeExporter` is deprecated, please use `components.customNodeExporter`.', params.customNodeExporter)
    else {},
  ),

  capacityAlerts: capacityAlerts + com.makeMergeable({
    [if std.objectHas(params.capacityAlerts, 'enabled') then 'enabled']: std.trace('Parameter `capacityAlerts.enabled` is deprecated, please use `components.capacityAlerts.enabled`.', params.capacityAlerts.enabled),
    [if std.objectHas(params.capacityAlerts, 'groupByNodeLabels') then 'groupByNodeLabels']: std.trace('Parameter `capacityAlerts.groupByNodeLabels` is deprecated, please use `components.capacityAlerts.groupByNodeLabels`.', params.capacityAlerts.groupByNodeLabels),
    [if std.objectHas(params.capacityAlerts, 'groups') then 'groups']: std.trace('Parameter `capacityAlerts.groups` is deprecated, please use `components.capacityAlerts`.', params.capacityAlerts.groups),
  }),
  alerts: alerts,

  alertManagerConfig: alertManagerConfig + com.makeMergeable(
    if std.objectHas(params, 'alertManagerConfig') then
      std.trace('Parameter `alertManagerConfig` is deprecated, please use `components.alertManager.config`.', params.alertManagerConfig)
    else {},
  ),
  alertManagerAutoDiscovery: alertManagerAutoDiscovery + com.makeMergeable(
    if std.objectHas(params, 'alertManagerAutoDiscovery') then
      std.trace('Parameter `alertManagerAutoDiscovery` is deprecated, please use `components.alertManagerAutoDiscovery`.', params.alertManagerAutoDiscovery)
    else {},
  ),

  silence: silence,
}
