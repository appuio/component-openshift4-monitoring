local monitoringOperator = import 'cluster-monitoring-operator/main.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;
local customAnnotations = params.alerts.customAnnotations;
local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};

local alertLabels = {
  syn: 'true',
  syn_component: 'openshift4-monitoring',
  severity: 'warning',
};

local predict(indicator, range='1d', resolution='5m', predict='3*24*60*60') =
  'predict_linear(avg_over_time(%(indicator)s[%(range)s:%(resolution)s])[%(range)s:%(resolution)s], %(predict)s)' %
  { indicator: indicator, range: range, resolution: resolution, predict: predict };

local filterWorkerNodes(metric, workerRole='app', nodeLabel='node') =
  '%(metric)s * on(%(nodeLabel)s) group_left label_replace(kube_node_role{role="%(workerRole)s"}, "%(nodeLabel)s", "$1", "node", "(.+)")' %
  { metric: metric, nodeLabel: nodeLabel, workerRole: workerRole };

local resourceCapacity(resource) = 'sum(%s)' % filterWorkerNodes('kube_node_status_capacity{resource="%s"}' % resource);
local resourceAllocatable(resource) = 'sum(%s)' % filterWorkerNodes('kube_node_status_allocatable{resource="%s"}' % resource);
local resourceRequests(resource) = 'sum(%s)' % filterWorkerNodes('kube_pod_resource_request{resource="%s"}' % resource);

local memoryCapacity = resourceCapacity('memory');
local memoryAllocatable = resourceAllocatable('memory');
local memoryRequests = resourceRequests('memory');
local memoryFree = 'sum(%s)' % filterWorkerNodes('node_memory_MemAvailable_bytes', nodeLabel='instance');

local cpuCapacity = resourceCapacity('cpu');
local cpuAllocatable = resourceAllocatable('cpu');
local cpuRequests = resourceRequests('cpu');
local cpuIdle = 'sum(%s)' % filterWorkerNodes('rate(node_cpu_seconds_total{mode="idle"}[15m])', nodeLabel='instance');

local podCapacity = resourceCapacity('pods');
local podCount = 'sum(%s)' % filterWorkerNodes('kubelet_running_pods');

local exprMap = {
  TooManyPods: function(arg) '%s - %s < %f * %s' % [ podCapacity, podCount, arg.factor, arg.threshold ],
  ExpectTooManyPods: function(arg) '%s - %s < %f * %s' % [ podCapacity, predict(podCount, range=arg.range, predict=arg.predict), arg.factor, arg.threshold ],

  TooMuchMemoryRequested: function(arg) '%s - %s < %f * %s' % [ memoryAllocatable, memoryRequests, arg.factor, arg.threshold ],
  ExpectTooMuchMemoryRequested: function(arg) '%s - %s < %f * %s' % [ memoryAllocatable, predict(memoryRequests, range=arg.range, predict=arg.predict), arg.factor, arg.threshold ],
  TooMuchCPURequested: function(arg) '%s - %s < %f * %s' % [ cpuAllocatable, cpuRequests, arg.factor, arg.threshold ],
  ExpectTooMuchCPURequested: function(arg) '%s - %s < %f * %s' % [ cpuAllocatable, predict(cpuRequests, range=arg.range, predict=arg.predict), arg.factor, arg.threshold ],

  ClusterLowOnMemory: function(arg) '%s < %f * %s' % [ memoryFree, arg.factor, arg.threshold ],
  ExpectClusterLowOnMemory: function(arg) '%s < %f * %s' % [ predict(memoryFree, range=arg.range, predict=arg.predict), arg.factor, arg.threshold ],

  ClusterCpuUsageHigh: function(arg) '%s < %f * %s' % [ cpuIdle, arg.factor, arg.threshold ],
  ExpectClusterCpuUsageHigh: function(arg) '%s < %f * %s' % [ predict(cpuIdle, range=arg.range, predict=arg.predict), arg.factor, arg.threshold ],
};

{
  rules: prom.PrometheusRule('capacity') {
    metadata+: {
      annotations+: defaultAnnotations,
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
  },
}
