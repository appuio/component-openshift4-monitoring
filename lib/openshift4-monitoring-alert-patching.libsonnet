// Component library providing generally applicable functions which adjust
// arbitrary alert rules to adhere to the format required by the component's
// approach for allowing us to patch upstream rules.
local com = import 'lib/commodore.libjsonnet';

local inv = com.inventory();

(import 'syn/alerts.libsonnet') {
  // Inject `openshift4_monitoring.alerts` as `global_alert_params` for the
  // generic library. The library will read `ignoreNames` and
  // `customAnnotations` from this parameter in addition to the respective
  // function parameters.
  global_alert_params+:: std.get(
    inv.parameters,
    'openshift4_monitoring',
    { alerts: {} }
  ).alerts,
}
