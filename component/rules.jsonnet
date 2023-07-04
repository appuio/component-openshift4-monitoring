local monitoringOperator = import 'cluster-monitoring-operator/main.jsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;
local customAnnotations = params.alerts.customAnnotations;
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
            message: '{{ $labels.node }}: Memory usage more than 97% (current value is: {{ $value | humanizePercentage }})%',
          },
        },
      ],
    } ] + std.flatMap(
      function(obj)
        if com.getValueOrDefault(obj, 'kind', '') == 'PrometheusRule' then
          // handle case for empty PrometheusRule objects
          com.getValueOrDefault(obj, 'spec', { groups: [] }).groups
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
      alertpatching.filterRules(group, params.alerts.ignoreNames)
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
  std.join('|', com.renderArray(params.alerts.includeNamespaces));

local patchExpr(expr) =
  std.strReplace(
    expr,
    'namespace=~"(openshift-.*|kube-.*|default)"',
    'namespace=~"(%s)"' % renderedNamespaceSelector
  );

local rulePatches =
  com.getValueOrDefault(
    params.alerts.patchRules,
    params.manifests_version,
    {}
  );

local patchRules = {
  spec+: {
    groups: std.map(
      function(group)
        group {
          rules: std.map(
            function(rule) alertpatching.patchRule(rule, rulePatches, false) {
              expr: patchExpr(super.expr),
            },
            group.rules
          ),
        },
      super.groups
    ),
  },
};

local patchPrometheusStackRules =
  local ignoreUserWorkload =
    com.renderArray(params.alerts.ignoreUserWorkload);
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
        com.renderArray(params.alerts.ignoreWarnings),
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
        if !std.member(com.renderArray(params.alerts.ignoreGroups), group.name)
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

{
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
}
