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

local filterRules(group, ignoreNames=[]) =
  group {
    rules:
      std.filter(
        // Filter out unwanted rules
        function(rule)
          if std.objectHas(rule, 'alert') then
            !std.member(ignoreNames, rule.alert),
        super.rules
      ),
  };

local filterPatchRules(group, config) =
  filterRules(group, config.ignoreNames) {
    rules: std.map(
      function(rule) patchRule(rule, config),
      super.rules
    ),
  };

local parse(rule, configGlobal, configComponent) =
  local config = {
    ignoreGroups: std.set(configGlobal.ignoreGroups + std.get(configComponent, 'ignoreGroups', [])),
    ignoreNames: std.set(configGlobal.ignoreNames + std.get(configComponent, 'ignoreNames', [])),
    ignoreWarnings: std.set(configGlobal.ignoreWarnings + std.get(configComponent, 'ignoreWarnings', [])),
    // teamLabel in configComponent overrides configGlobal
    teamLabel: if std.get(configComponent, 'teamLabel', '') != '' then std.get(configComponent, 'teamLabel', null) else configGlobal.teamLabel,
    // configGlobal overrides configComponent
    customAnnotations: std.get(configComponent, 'customAnnotations', {}) + makeMergeable(configGlobal.customAnnotations),
    patchRules: std.get(configComponent, 'patchRules', {}) + makeMergeable(configGlobal.patchRules),
  };
  {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      name: 'syn-' + rule.metadata.name,
      namespace: rule.metadata.namespace,
      labels+: {
        'espejote.io/created-by': 'openshift4-monitoring-rules',
      },
      ownerReferences: [ {
        controller: true,
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        name: rule.metadata.name,
        uid: rule.metadata.uid,
      } ],
    },
    spec: {
      groups: [
        filterPatchRules(group, config)
        for group in rule.spec.groups
        if !std.member(config.ignoreGroups, group)
      ],
    },
  };

{
  parse: parse,
}
