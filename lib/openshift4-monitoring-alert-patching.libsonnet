// Component library providing generally applicable functions which adjust
// arbitrary alert rules to adhere to the format required by the component's
// approach for allowing us to patch upstream rules.
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();

local global_alert_params =
  std.get(
    inv.parameters,
    'openshift4_monitoring',
    { alerts: { ignoreNames: [] } }
  ).alerts;

/**
 * \brief filter alert rules in the provided group
 *
 * The function assumes that `group` is a valid entry for the PrometheusRule
 * CR `.spec.groups` field.
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
 * \arg preserveRecordingRules
 *        Whether to keep or discard recording rules in the group. This
 *        argument is optional and defaults to `false`. This is useful when
 *        wanting to patch alerting rules which are already deployed to the
 *        cluster through some operator (e.g. cluster-logging, or rook-ceph).
 *        Generally, in such cases, we'll only want to modify alerting rules,
 *        but don't want to deploy duplicates of the recording rules which may
 *        be present in the same groups as the alerting rules in the upstream
 *        manifests.
 *
 * \returns
 *    The group with alert rules whose field `alert` matches an entry in either
 *    component parameter `openshift4_monitoring.alerts.ignoreNames` or the
 *    function argument `ignoreNames` list removed. If `preserveRecordingRules`
 *    is `false`, all recording rules are also removed from the result.
 */
local filterRules(group, ignoreNames=[], preserveRecordingRules=false) =
  local filterRecording(rule) =
    if preserveRecordingRules then
      true
    else
      // only create duplicates of alert rules
      std.objectHas(rule, 'alert');
  local ignore_set = std.set(global_alert_params.ignoreNames + ignoreNames);
  group {
    rules:
      std.filter(
        // Filter out unwanted rules
        function(rule)
          filterRecording(rule) &&
          !std.member(ignore_set, rule.alert),
        super.rules
      ),
  };

/**
 * \brief patch the provided rule to adhere to the format expected by the
 *        component.
 *
 * This function patches the provided alert rule to adhere to the format
 * expected by this component. This includes adding labels which are used by
 * other parts of the component to the rule (e.g. `syn=true`), as well as
 * ensuring that the alert name is prefixed with `SYN_`.
 *
 * Custom alert patches can be provided through argument `patches`.
 *
 * Recording rules will always be returned unchanged
 *
 * \arg rule
 *        The rule to patch
 * \arg patches
 *        An object with partial alert rule definitions. The function uses the
 *        provided rule's `alert` field to lookup potential patches. This
 *        parameter is optional and defaults to an empty object.
 * \arg patchName
 *        Whether to prefix the alert name with `SYN_` if it isn't already.
 *        This parameter is optional and defaults to `true`.
 *
 * \returns The patched rule
 */
local patchRule(rule, patches={}, patchName=true) =
  if !std.objectHas(rule, 'alert') then
    rule
  else
    local rulepatch = std.get(patches, rule.alert, {});
    local fixupName(name) =
      if patchName && !std.startsWith(name, 'SYN_') then
        'SYN_' + name
      else
        name;
    rule {
      // Change alert names so we don't get multiple alerts with the same
      // name, as the logging operator deploys its own copy of these
      // rules.
      alert: fixupName(super.alert),
      labels+: {
        syn: 'true',
        // mark alert as belonging to component instance in whose context the
        // function is called.
        syn_component: inv.parameters._instance,
      },
    } + com.makeMergeable(rulepatch);

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
 * \arg preserveRecordingRules
 *        Whether to keep or discard recording rules in the group. This
 *        argument is optional and defaults to `false`. This is useful when
 *        wanting to patch alerting rules which are already deployed to the
 *        cluster through some operator (e.g. cluster-logging, or rook-ceph).
 *        Generally, in such cases, we'll only want to modify alerting rules,
 *        but don't want to deploy duplicates of the recording rules which may
 *        be present in the same groups as the alerting rules in the upstream
 *        manifests.
 * \arg patchNames
 *        Whether to prefix alert names with `SYN_` if they aren't already.
 *        This parameter is passed to `patchRule()` as argument `patchName`.
 *        This parameter is optional and defaults to `true`.
 *
 * \returns the provided `group` object with rules filtered and patched
 */
local filterPatchRules(group, ignoreNames=[], patches={}, preserveRecordingRules=false, patchNames=true) =
  filterRules(group, ignoreNames, preserveRecordingRules) {
    rules: std.map(
      function(rule) patchRule(rule, patches, patchNames),
      super.rules
    ),
  };

{
  filterRules: filterRules,
  patchRule: patchRule,
  filterPatchRules: filterPatchRules,
}
