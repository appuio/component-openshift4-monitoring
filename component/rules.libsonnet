// main template for openshift4-monitoring
local monitoringOperator = import 'cluster-monitoring-operator/main.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Configuration

local _defaultsAlerts = {
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
};

local configAlerts = _defaultsAlerts + com.makeMergeable(params.alerts);

// Helpers

local customAnnotations = configAlerts.customAnnotations;
local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};

local alertpatching = import 'lib/alert-patching.libsonnet';

local upstreamManifestsFileExclude = function(file) (
  (
    params.upstreamRules.networkPlugin != 'ovn-kubernetes' &&
    (
      file == 'ovn-kubernetes-control-plane.yaml' ||
      file == 'ovn-kubernetes.yaml'
    )
  )
  || (
    params.upstreamRules.networkPlugin != 'openshift-sdn' &&
    file == 'openshift-sdn.yaml'
  )
  || (
    inv.parameters.facts.cloud != 'vsphere' &&
    file == 'vsphere-problem-detector-rules.yaml'
  )
);

local loadFiles(root) =
  local fpath = '%s/%s' % [ root, params.manifests_version ];
  std.flatMap(
    function(file)
      std.parseJson(kap.yaml_load_stream('%s/%s' % [ fpath, file ])),
    std.filter(
      function(file)
        !upstreamManifestsFileExclude(file),
      kap.dir_files_list(fpath)
    )
  );

local fileRoots = [
  'openshift4-monitoring/manifests',
  'compiled/openshift4-monitoring/prerendered_manifests',
];

local upstreamManifests = std.flattenArrays(
  [
    loadFiles(root)
    for root in fileRoots
  ]
);

// Currently this function can only render the following gotemplate
// expressions:
// * '{{"{{"}}' -> '{{'
// * '{{"}}"}}' -> '}}'
local simpleRenderGoTemplate(groups) =
  // We only try to render gotemplates in the rule groups listed in this
  // variable.
  local rulegroups = [
    'cluster-network-operator-master.rules',
    'cluster-network-operator-ovn.rules',
  ];
  [
    if std.member(rulegroups, g.name) then
      g {
        rules: [
          if std.objectHas(r, 'alert') then
            // only try to render templates in alerting rules
            r {
              annotations+: {
                summary: std.strReplace(
                  std.strReplace(r.annotations.summary, '{{"{{"}}', '{{'), '{{"}}"}}', '}}'
                ),
              },
            }
          else
            r
          for r in g.rules
        ],
      }
    else
      g
    for g in groups
  ];

local additionalRules = {
  spec+: {
    groups+: [ {
      name: 'node-utilization',
      rules: [
        {
          alert: 'node_cpu_load5',
          expr: 'max by(instance) (node_load5) / count by(instance) (node_cpu_info) > 2',
          'for': '30m',
          labels: {
            severity: 'critical',
          },
          annotations: {
            message: '{{ $labels.instance }}: Load higher than 2 (current value is: {{ $value }})',
          },
        },
        {
          alert: 'node_memory_free_percent',
          expr: '(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.97',
          'for': '30m',
          labels: {
            severity: 'critical',
          },
          annotations: {
            message: '{{ $labels.instance }}: Memory usage more than 97% (current value is: {{ $value | humanizePercentage }})%',
          },
        },
        {
          alert: 'NodeTcpMemoryUtilizationHigh',
          expr: 'node_sockstat_TCP_mem_bytes > on(instance) node_memory_MemTotal_bytes*0.0625',
          'for': '30m',
          labels: {
            severity: 'critical',
          },
          annotations: {
            message: 'TCP memory usage is high on {{ $labels.instance }}',
            description: |||
              TCP memory usage exceeds the TCP memory pressure threshold on node {{ $labels.instance }}.

              Check the node for processes with unusual amounts of TCP sockets.
            |||,
            runbook_url: 'https://hub.syn.tools/openshift4-monitoring/runbooks/tcp-memory-usage.html',
          },
        },
      ],
    } ] + std.flatMap(
      function(obj)
        if com.getValueOrDefault(obj, 'kind', '') == 'PrometheusRule' then
          // handle case for empty PrometheusRule objects
          local groups = com.getValueOrDefault(obj, 'spec', { groups: [] }).groups;
          simpleRenderGoTemplate(groups)
        else if std.objectHas(obj, 'groups') then
          obj.groups
        else
          [],
      upstreamManifests
    ),
  },
};

local filterRules = {
  spec+: {
    groups: [
      alertpatching.filterRules(group, configAlerts.ignoreNames)
      for group in super.groups
    ],
  },
};

local annotateRules = {
  spec+: {
    groups: std.map(
      function(group)
        group {
          rules: std.map(
            function(rule)
              // Only add custom annotations to alert rules, since recording
              // rules cannot have annotations.
              // We identify alert rules by the presence of the `alert` field.
              if std.objectHas(rule, 'alert') then
                rule {
                  annotations+: defaultAnnotations,
                }
              else
                rule,
            group.rules
          ),
        },
      super.groups
    ),
  },
};

local renderedNamespaceSelector =
  std.join('|', com.renderArray(configAlerts.includeNamespaces));

local renderedExcludesSelector =
  std.join('|', com.renderArray(configAlerts.excludeNamespaces));

local renderedSelector =
  local hasNsSel = std.length(renderedNamespaceSelector) > 0;
  local hasExcSel = std.length(renderedExcludesSelector) > 0;
  (
    if hasNsSel then
      'namespace=~"(%s)"' % renderedNamespaceSelector
    else ''

  ) + (
    if hasNsSel && hasExcSel then ',' else ''
  ) + (
    if std.length(renderedExcludesSelector) > 0 then
      'namespace!~"(%s)"' % renderedExcludesSelector
    else ''
  );

local patchExpr(expr) =
  std.strReplace(
    expr,
    'namespace=~"(openshift-.*|kube-.*|default)"',
    renderedSelector
  );

local rulePatches =
  std.get(configAlerts.patchRules, '*', {}) +
  com.makeMergeable(std.get(
    configAlerts.patchRules,
    params.manifests_version,
    {}
  ));

local patchRules = {
  spec+: {
    groups: std.map(
      function(group)
        group {
          rules: std.map(
            function(rule)
              alertpatching.patchRule(rule, rulePatches, false) {
                // NOTE(sg): Make runbook_url annotation visible so we can
                // always patch it. This is necessary because some upstream
                // Jsonnet hides the annotation with `runbook_url::` for
                // alerts where they don't want to set the annotation.
                annotations+:
                  if std.objectHasAll(rule.annotations, 'runbook_url') then {
                    runbook_url::: super.runbook_url,
                  } else {},
                expr: patchExpr(super.expr),
              } + { annotations: std.prune(super.annotations) },
            group.rules
          ),
        },
      super.groups
    ),
  },
};

local patchPrometheusStackRules =
  local ignoreUserWorkload =
    com.renderArray(configAlerts.ignoreUserWorkload);
  local dropUserWorkload(alertname) = std.member(ignoreUserWorkload, alertname);

  local replacers = [
    function(e)
      std.strReplace(
        e,
        'namespace=~"openshift-monitoring|openshift-user-workload-monitoring"',
        'namespace="openshift-monitoring"'
      ),
    function(e)
      std.strReplace(
        e,
        'job=~"alertmanager-main|alertmanager-user-workload"',
        'job="alertmanager-main"'
      ),
    function(e)
      std.strReplace(
        e,
        'job=~"prometheus-k8s|prometheus-user-workload"',
        'job="prometheus-k8s"'
      ),
  ];

  local patch_selector(field) =
    std.foldl(function(e, r) r(e), replacers, field);

  if std.length(ignoreUserWorkload) == 0 then
    {}
  else
    {
      spec+: {
        groups: std.map(
          function(group)
            group {
              rules: std.map(
                function(rule)
                  if (
                    std.objectHas(rule, 'alert') &&
                    dropUserWorkload(rule.alert)
                  ) then
                    rule {
                      expr: patch_selector(super.expr),
                      [if std.objectHas(rule.annotations, 'description') then 'annotations']+: {
                        description: patch_selector(super.description),
                      },
                    }
                  else
                    rule,
                group.rules
              ),
            },
          super.groups
        ),
      },
    };

local cmoRules =
  std.foldl(
    function(acc, it) acc + it,
    std.map(
      com.makeMergeable,
      [
        monitoringOperator['alertmanager/prometheusRule'],
        monitoringOperator['cluster-monitoring-operator/prometheusRule'],
        monitoringOperator['control-plane/prometheusRule'],
        monitoringOperator['kube-state-metrics/prometheusRule'],
        monitoringOperator['node-exporter/prometheusRule'],
        monitoringOperator['prometheus-k8s/prometheusRule'],
        monitoringOperator['prometheus-operator/prometheusRule'],
        com.getValueOrDefault(
          monitoringOperator,
          'prometheus-operator/prometheusRuleValidatingWebhook',
          {}
        ),
        monitoringOperator['thanos-querier/prometheusRule'],
        monitoringOperator['thanos-ruler/thanosRulerPrometheusRule'],
      ],
    ),
    {}
  );

local etcdRules = com.makeMergeable(import 'cluster-etcd-operator/main.jsonnet');

local dropRules =
  local drop(rule) =
    (std.get(rule.labels, 'severity', '') == 'info') ||
    (
      std.get(rule.labels, 'severity', '') == 'warning' &&
      std.member(
        com.renderArray(configAlerts.ignoreWarnings),
        std.get(rule, 'alert', '')
      )
    );
  {
    spec+: {
      groups: [
        group {
          rules: std.filter(function(rule) !drop(rule), super.rules),
        }
        for group in super.groups
        if !std.member(com.renderArray(configAlerts.ignoreGroups), group.name)
      ],
    },
  };

local rules =
  std.foldl(
    function(x, y)
      x {
        [y.name]+: com.makeMergeable(y),
      },
    (
      cmoRules
      + etcdRules
      + additionalRules
      + annotateRules
      + filterRules
      + dropRules
      + patchRules
      + patchPrometheusStackRules
    ).spec.groups,
    {},
  );

// Manifests

local alerts = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'syn-k8s-rules',
    namespace: 'openshift-monitoring',
    labels: {
      role: 'alert-rules',
    },
  },
  spec: {
    groups:
      std.filter(
        function(group) std.length(group.rules) > 0,
        [
          {
            local group = rules[alertGroupName],
            name: 'syn-' + group.name,
            rules: std.sort([
              rule {
                alert: if rule.alert != 'Watchdog' then
                  'SYN_' + rule.alert
                else
                  rule.alert,
                labels+: {
                  syn: 'true',
                },
              }
              for rule in group.rules
            ], function(r) r.alert),
          }
          for alertGroupName in std.sort(std.objectFields(rules))
        ]
      ),
  },
};

local customRules = prom.generateRules('custom-rules', params.rules);

// Define outputs below
{
  '40_rules': alerts,
  [if std.length(params.rules) > 0 then '40_rules_custom']: customRules,
}
