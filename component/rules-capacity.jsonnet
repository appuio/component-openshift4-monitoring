local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

/* --- Capacity Rules ------------------------------------------------------- */

local byLabels = com.renderArray(params.capacityAlerts.groupByNodeLabels);
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

local getExpr = function(group, rule) params.capacityAlerts.groups[group].rules[rule].expr;
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

local capacityRules = prom.PrometheusRule('capacity') {
  metadata: {
    annotations: defaultAnnotations,
    labels+: {
      'espejote.io/ignore': 'openshift4-monitoring-rules',
    },
    name: 'syn-capacity-rules',
    namespace: params.namespace,
  },
  spec+: {
    groups: std.filter(function(x) std.length(x.rules) > 0, [
      {
        local group = params.capacityAlerts.groups[alertGroupName],
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
      for alertGroupName in std.objectFields(params.capacityAlerts.groups)
    ]),
  },
};

{
  [if params.capacityAlerts.enabled then '50_rules_capacity']: capacityRules,
}
