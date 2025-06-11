// Helpers from commodore.libsonnet

local makeMergeable(o) = {
  [key]+: makeMergeable(o[key])
  for key in std.objectFields(o)
  if std.isObject(o[key])
} + {
  [key]+: o[key]
  for key in std.objectFields(o)
  if std.isArray(o[key])
} + {
  [key]: o[key]
  for key in std.objectFields(o)
  if !std.isObject(o[key]) && !std.isArray(o[key])
};

local renderArray(arr) =
  local realval(v) = std.lstripChars(v, '~');
  local val_state = std.foldl(
    function(a, it) a + it,
    [
      assert
        std.isString(v) :
        "renderArray() doesn't support arrays with non-string entries";
      { [realval(v)]: !std.startsWith(v, '~') }
      for v in arr
    ],
    {}
  );
  std.filter(
    function(val) val_state[val],
    std.objectFields(val_state)
  );

// Actual rendering

// Apply this last to avoid problems with alert name matching
local procPatchRules(group, config) =
  group {
    rules: [
      if std.objectHas(rule, 'alert') then
        rule {
          // Change alert names so we don't get multiple alerts with the same name
          // Ensure Watchdog is not renamed
          alert: if super.alert == 'Watchdog' then 'Watchdog' else 'SYN_' + super.alert,
          labels+: {
            syn: 'true',
            // mark alert as belonging to component instance in whose context the
            // function is called.
            syn_component: config.componentName,
            // mark alert as belonging to the team in whose context the
            // function is called.
            [if config.teamLabel != null then 'syn_team']: config.teamLabel,
          },
        } + makeMergeable(std.get(config.patchRules, rule.alert, {}))
      else
        // If the rule doesn't have an alert field, return it unchanged (eg. recording rules)
        rule
      for rule in super.rules
    ],
  };

local procPatchExprUserWorkload(group, config) =
  local dropUserWorkload(alert) = std.member(config.ignoreUserWorkload, alert);
  local patchSelectors(field) = std.foldl(
    function(f, patch_fn) patch_fn(f),
    [
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
    ],
    field
  );
  group {
    rules: [
      if dropUserWorkload(std.get(rule, 'alert', '')) then
        rule {
          expr: patchSelectors(super.expr),
          // I have no clue what this part is originally for.
          // I know what it does, just not why...
          [if std.objectHas(std.get(rule, 'annotations', {}), 'description') then 'annotations']+: {
            description: patchSelectors(super.description),
          },
        }
      else
        rule
      for rule in super.rules
    ],
  };

local procPatchExprSelector(group, config) =
  local markerOpenshiftNamespace = 'namespace=~"(openshift-.*|kube-.*|default)"';
  // Replace namespace selector in expression
  local hasNamespaceSelector = std.length(config.renderedIncludeSelector) > 0;
  local hasExclusionSelector = std.length(config.renderedExcludeSelector) > 0;
  group {
    rules: [
      rule {
        expr: std.strReplace(
          super.expr,
          markerOpenshiftNamespace,
          (
            if hasNamespaceSelector then
              'namespace=~"(%s)"' % config.renderedIncludeSelector
            else ''

          ) + (
            if hasNamespaceSelector && hasExclusionSelector then ',' else ''
          ) + (
            if hasExclusionSelector then
              'namespace!~"(%s)"' % config.renderedExcludeSelector
            else ''
          )
        ),
      }
      for rule in super.rules
    ],
  };

local procFilterRules(group, config) =
  local getSeverity(r) = std.get(std.get(r, 'labels', {}), 'severity', '');
  local drop(r) =
    // drop rules with severity info
    (
      getSeverity(r) == 'info'
    ) ||
    // drop rules with severity warning that are in the ignoreWarnings list
    (
      getSeverity(r) == 'warning' &&
      std.member(
        config.ignoreWarnings,
        std.get(r, 'alert', '')
      )
    ) ||
    // drop rules with alert name in the ignoreNames list
    (
      std.member(
        config.ignoreNames,
        std.get(r, 'alert', '')
      )
    );
  group {
    rules: std.filter(function(rule) !drop(rule), super.rules),
  };

local processGroup(group, config) = std.foldl(
  function(g, func) func(g, config),
  [
    procFilterRules,
    procPatchExprSelector,
    procPatchExprUserWorkload,
    procPatchRules,
  ],
  group
);

local process(rule, configGlobal, configComponent, enableOwnerRefrences=true) =
  local config = {
    ignoreGroups: renderArray(configGlobal.ignoreGroups + std.get(configComponent, 'ignoreGroups', [])),
    ignoreNames: renderArray(configGlobal.ignoreNames + std.get(configComponent, 'ignoreNames', [])),
    ignoreWarnings: renderArray(configGlobal.ignoreWarnings + std.get(configComponent, 'ignoreWarnings', [])),
    // ignoreUserWorkload only available in configGlobal
    ignoreUserWorkload: renderArray(configGlobal.ignoreUserWorkload),
    // teamLabel in configComponent overrides configGlobal
    teamLabel: if std.get(configComponent, 'teamLabel', '') != '' then std.get(configComponent, 'teamLabel', null) else configGlobal.teamLabel,
    // configGlobal overrides configComponent
    patchRules: std.get(configComponent, 'patchRules', {}) + makeMergeable(configGlobal.patchRules),
    // include and exclude namespaces from expressionsv
    renderedIncludeSelector: std.join('|', renderArray(configGlobal.includeNamespaces + std.get(configComponent, 'includeNamespaces', []))),
    renderedExcludeSelector: std.join('|', renderArray(configGlobal.excludeNamespaces + std.get(configComponent, 'excludeNamespaces', []))),
    componentName: std.get(configComponent, 'component', 'openshift4-monitoring'),
  };
  {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      labels+: {
        'espejote.io/created-by': 'openshift4-monitoring-rules',
      },
      [if enableOwnerRefrences then 'ownerReferences']: [ {
        controller: true,
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        name: rule.metadata.name,
        uid: rule.metadata.uid,
      } ],
      name: 'syn-' + rule.metadata.name,
      namespace: rule.metadata.namespace,
    },
    spec: {
      groups: [
        // Process each group and drop groups in `config.ignoreGroups`
        processGroup(group, config)
        for group in rule.spec.groups
        if !std.member(config.ignoreGroups, group.name)
      ],
    },
  };

{
  process: process,
}
