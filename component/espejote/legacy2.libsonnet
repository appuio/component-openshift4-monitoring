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

local patchRule(rule, patches={}, customAnnotations={}, teamLabel=null) =
  // If the rule doesn't have an alert field, return it unchanged (eg. recording rules)
  if !std.objectHas(rule, 'alert') then
    rule
  else
    rule {
      // Change alert names so we don't get multiple alerts with the same name
      alert: 'SYN_' + super.alert,
      labels+: {
        syn: 'true',
        // mark alert as belonging to component instance in whose context the
        // function is called.
        syn_component: 'openshift4-monitoring',
        // mark alert as belonging to the team in whose context the
        // function is called.
        [if teamLabel != null then 'syn_team']: teamLabel,
      },
      annotations+:
        std.get(customAnnotations, super.alert, {}),
    } + makeMergeable(std.get(patches, rule.alert, {}));

/**
 * \brief Convenience wrapper around filterRules and patchRule.
 *
 * This function provides a convenience wrapper which filters the provided
 * group using `filterRules`, and applies `patchRule` for each rule which
 * isn't dropped by `filterRules`.
 *
 * \arg group
 *        a PrometheusRule CR `.spec.groups` entry
 * \arg ignoreNames
 *        A list of alert names to filter out. This argument is optional and
 *        defaults to the empty list.  The function doesn't process the
 *        provided value for `ignoreNames`, except converting it to a Jsonnet
 *        set with `std.set()`.  If you want to use `com.renderArray()` to
 *        allow re-enabling ignored alerts, you'll have to do so before
 *        providing the list to the function.
 * \arg patches
 *        An object with partial alert rule definitions. The function uses the
 *        provided rule's `alert` field to lookup potential patches. This
 *        parameter is optional and defaults to an empty object.
 * \arg customAnnotations
 *        A map of custom annotations to add to the alert rule. This parameter
 *        is optional and defaults to an empty object.
 * \arg teamLabel
 *        The team label to add to the alert rule. This parameter is optional.
 *
 * \returns the provided `group` object with rules filtered and patched
 */
local filterPatchRules(group, ignoreNames=[], patches={}, customAnnotations={}, teamLabel=null) =
  filterRules(group, ignoreNames) {
    rules: std.map(
      function(rule) patchRule(rule, patches, customAnnotations, teamLabel),
      super.rules
    ),
  };

{
  filterPatchRules: filterPatchRules,
}
