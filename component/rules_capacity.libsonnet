// main template for openshift4-monitoring
local monitoringOperator = import 'cluster-monitoring-operator/main.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Configuration: Defaults and Legacy

local _defaultsCapacityAlerts = {
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

local _legacyCapacityAlerts = com.makeMergeable({
  [if std.objectHas(params.capacityAlerts, 'enabled') then 'enabled']: std.trace('Parameter `capacityAlerts.enabled` is deprecated, please use `components.capacityAlerts.enabled`.', params.capacityAlerts.enabled),
  [if std.objectHas(params.capacityAlerts, 'groupByNodeLabels') then 'groupByNodeLabels']: std.trace('Parameter `capacityAlerts.groupByNodeLabels` is deprecated, please use `components.capacityAlerts.groupByNodeLabels`.', params.capacityAlerts.groupByNodeLabels),
  [if std.objectHas(params.capacityAlerts, 'groups') then 'groups']: std.trace('Parameter `capacityAlerts.groups` is deprecated, please use `components.capacityAlerts`.', params.capacityAlerts.groups),
});

local configCapacityAlerts = _defaultsCapacityAlerts + _legacyCapacityAlerts;

// Helpers

local customAnnotations = params.alerts.customAnnotations;
local byLabels = com.renderArray(configCapacityAlerts.groupByNodeLabels);
local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};

local alertLabels = {
  severity: 'warning',
  syn: 'true',
  syn_component: 'openshift4-monitoring',
  [if std.objectHas(inv.parameters, 'syn') then 'syn_team']: std.get(inv.parameters.syn, 'owner', ''),
};

local predict(indicator, range='1d', resolution='5m', predict='3*24*60*60') =
  'predict_linear(avg_over_time(%(indicator)s[%(range)s:%(resolution)s])[%(range)s:%(resolution)s], %(predict)s)' %
  { indicator: indicator, range: range, resolution: resolution, predict: predict };


local addNodeLabels(metric) =
  if std.length(byLabels) > 0 then
    '%(metric)s * on(node) group_left(%(labelList)s) kube_node_labels' %
    { metric: metric, labelList: std.join(', ', byLabels) }
  else
    metric;

local renameNodeLabel(expression, nodeLabel) =
  if nodeLabel == 'node' then
    expression
  else
    'label_replace(%(expression)s, "node", "$1", "%(nodeLabel)s", "(.+)")' %
    { expression: expression, nodeLabel: nodeLabel };

local filterWorkerNodes(metric, workerRole='app', nodeLabel='node') =
  addNodeLabels(
    '%(metric)s * on(node) group_left kube_node_role{role="%(workerRole)s"}' %
    { metric: renameNodeLabel(metric, nodeLabel), nodeLabel: nodeLabel, workerRole: workerRole }
  );

local aggregate(expression, aggregator='sum') =
  if std.length(byLabels) > 0 then
    '%(aggregator)s by (%(labelList)s) (%(expression)s)' %
    { expression: expression, labelList: std.join(', ', byLabels), aggregator: aggregator }
  else
    '%(aggregator)s(%(expression)s)' %
    { expression: expression, aggregator: aggregator };

local maxPerNode(resource) =
  aggregate(
    addNodeLabels(
      '(%s) * on(node) group_left kube_node_role{role="app"}' % resource,
    ),
    aggregator='max'
  );

local resourceCapacity(resource) = aggregate(filterWorkerNodes('kube_node_status_capacity{resource="%s"}' % resource));
local resourceAllocatable(resource) = aggregate(filterWorkerNodes('kube_node_status_allocatable{resource="%s"}' % resource));
local resourceRequests(resource) = aggregate(filterWorkerNodes('kube_pod_resource_request{resource="%s"}' % resource));

local memoryRequestsThreshold = maxPerNode('kube_node_status_allocatable{resource="memory"}');
local memoryThreshold = maxPerNode('kube_node_status_capacity{resource="memory"}');
local memoryAllocatable = resourceAllocatable('memory');
local memoryRequests = resourceRequests('memory');
local memoryFree = aggregate(filterWorkerNodes('node_memory_MemAvailable_bytes', nodeLabel='instance'));

local cpuRequestsThreshold = maxPerNode('kube_node_status_allocatable{resource="cpu"}');
local cpuThreshold = maxPerNode('kube_node_status_capacity{resource="cpu"}');
local cpuAllocatable = resourceAllocatable('cpu');
local cpuRequests = resourceRequests('cpu');
local cpuIdle = aggregate(filterWorkerNodes('rate(node_cpu_seconds_total{mode="idle"}[15m])', nodeLabel='instance'));

local podThreshold = maxPerNode('kube_node_status_capacity{resource="pods"}');
local podCapacity = resourceCapacity('pods');
local podCount = aggregate(filterWorkerNodes('kubelet_running_pods'));

local getExpr = function(group, rule) configCapacityAlerts.groups[group].rules[rule].expr;
local unusedReserved = getExpr('UnusedCapacity', 'ClusterHasUnusedNodes').reserved;

local exprMap = {
  TooManyPods: function(arg) '%s - %s < %f * %s' % [ podCapacity, podCount, arg.factor, podThreshold ],
  ExpectTooManyPods: function(arg) '%s - %s < %f * %s' % [ podCapacity, predict(podCount, range=arg.range, predict=arg.predict), arg.factor, podThreshold ],

  TooMuchMemoryRequested: function(arg) '%s - %s < %f * %s' % [ memoryAllocatable, memoryRequests, arg.factor, memoryRequestsThreshold ],
  ExpectTooMuchMemoryRequested: function(arg) '%s - %s < %f * %s' % [ memoryAllocatable, predict(memoryRequests, range=arg.range, predict=arg.predict), arg.factor, memoryRequestsThreshold ],
  TooMuchCPURequested: function(arg) '%s - %s < %f * %s' % [ cpuAllocatable, cpuRequests, arg.factor, cpuRequestsThreshold ],
  ExpectTooMuchCPURequested: function(arg) '%s - %s < %f * %s' % [ cpuAllocatable, predict(cpuRequests, range=arg.range, predict=arg.predict), arg.factor, cpuRequestsThreshold ],

  ClusterLowOnMemory: function(arg) '%s < %f * %s' % [ memoryFree, arg.factor, memoryThreshold ],
  ExpectClusterLowOnMemory: function(arg) '%s < %f * %s' % [ predict(memoryFree, range=arg.range, predict=arg.predict), arg.factor, memoryThreshold ],

  ClusterCpuUsageHigh: function(arg) '%s < %f * %s' % [ cpuIdle, arg.factor, cpuThreshold ],
  ExpectClusterCpuUsageHigh: function(arg) '%s < %f * %s' % [ predict(cpuIdle, range=arg.range, predict=arg.predict), arg.factor, cpuThreshold ],

  ClusterHasUnusedNodes: function(arg)
    '%s > %f' % [
      aggregate(
        |||
          (
            label_replace(
              (%s - %s) / %s
            , "resource", "pods", "", "")
          ) or (
            label_replace(
              (%s - %s) / %s
            , "resource", "requested_memory", "", "")
          ) or (
            label_replace(
              (%s - %s) / %s
            , "resource", "requested_cpu", "", "")
          ) or (
            label_replace(
              %s / %s
            , "resource", "memory", "", "")
          ) or (
            label_replace(
              %s / %s
            , "resource", "cpu", "", "")
          )
        ||| %
        [
          podCapacity,
          podCount,
          podThreshold,

          memoryAllocatable,
          memoryRequests,
          memoryRequestsThreshold,

          cpuAllocatable,
          cpuRequests,
          cpuRequestsThreshold,

          memoryFree,
          memoryThreshold,

          cpuIdle,
          cpuThreshold,
        ],

        'min'
      ),
      unusedReserved,
    ],
};

// Manifests

local capacityAlerts = prom.PrometheusRule('capacity') {
  metadata+: {
    annotations+: defaultAnnotations,
    namespace: params.namespace,
  },
  spec+: {
    groups: std.filter(function(x) std.length(x.rules) > 0, [
      {
        local group = configCapacityAlerts.groups[alertGroupName],
        name: 'syn-' + alertGroupName,
        rules: [
          group.rules[ruleName] {
            alert: 'SYN_' + ruleName,
            enabled:: true,
            labels: alertLabels + super.labels,
            annotations: defaultAnnotations + super.annotations,
            expr:
              if std.objectHas(super.expr, 'raw') then
                super.expr.raw
              else
                exprMap[ruleName](super.expr),
          }
          for ruleName in std.objectFields(group.rules)
          if group.rules[ruleName].enabled
        ],
      }
      for alertGroupName in std.objectFields(configCapacityAlerts.groups)
    ]),
  },
};

// Define outputs below
if configCapacityAlerts.enabled then
  {
    '40_rules_capacity': capacityAlerts,
  }
