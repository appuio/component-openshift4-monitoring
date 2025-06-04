local esp = import 'espejote.libsonnet';

local op_rules = esp.context().op_rules;
local config = import 'patch-operator-rules/config.json';
local alert_patching = import 'patch-operator-rules/alert-patching.libsonnet';

local filter_patch_rules(manifest) = [
  alert_patching.filterPatchRules(group, config.ignoreNames, config.patchRules, config.customAnnotations, config.teamLabel)
  for group in manifest.spec.groups
];

[
  {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'PrometheusRule',
    metadata: {
      name: 'syn-' + op_rule.metadata.name,
      // namespace: op_rule.metadata.namespace,
      labels+: {
        'espejote.io/created-by': 'monitoring-prometheusrules',
      },
      ownerReferences: [ {
        controller: true,
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        name: op_rule.metadata.name,
        uid: op_rule.metadata.uid,
      } ],
    },
    spec: {
      groups: [
        group
        for group in std.sort(filter_patch_rules(op_rule))
      ],
    },
  }
  for op_rule in op_rules
]
