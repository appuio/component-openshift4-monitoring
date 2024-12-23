/**
 * \file prom.libsonnet
 * \brief Helpers to create Prometheus Operator CRs.
 *        API reference: https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/api.md
 */

local kube = import 'lib/kube.libjsonnet';

local alertpatching = import 'lib/alert-patching.libsonnet';

// Define Prometheus Operator API versions
local api_version = {
  monitoring: 'monitoring.coreos.com/v1',
};

local prometheusRule(name) =
  kube._Object(api_version.monitoring, 'PrometheusRule', name);

{
  api_version: api_version,

  /**
  * \brief Helper to create PrometheusRule objects.
  *
  * \arg The name of the PrometheusRule.
  * \return A PrometheusRule object.
  */
  PrometheusRule(name): prometheusRule(name),

  /**
  * \brief Helper to create Prometheus objects.
  *
  * \arg The name of the Prometheus.
  * \return A Prometheus object.
  */
  Prometheus(name):
    kube._Object(api_version.monitoring, 'Prometheus', name),

  /**
  * \brief Helper to create ServiceMonitor objects.
  *
  * \arg The name of the ServiceMonitor.
  * \return A ServiceMonitor object.
  */
  ServiceMonitor(name):
    kube._Object(api_version.monitoring, 'ServiceMonitor', name),

  /**
  * \brief Helper to create Alertmanager objects.
  *
  * \arg The name of the Alertmanager.
  * \return A Alertmanager object.
  */
  Alertmanager(name):
    kube._Object(api_version.monitoring, 'Alertmanager', name),

  /**
   * \brief Function to render rules defined in the hierarchy
   *
   * This function assumes that the rules are defined in the hierarchy in an
   * object whose fields each represent a rule group. The function also
   * assumes that each rule group is defined as an object which uses scheme
   * '(alert:|record:)rulename' for the field names.
   *
   * \arg name the name for the resulting `PrometheusRule` manifest
   * \arg rules the object to render as rules

   * \return A single `PrometheusRule` manifest containing the rule groups.
   */
  generateRules(name, rules):
    prometheusRule(name) {
      spec: {
        groups: std.filter(
          function(g) std.length(g.rules) > 0,
          [
            {
              name: group_name,
              rules: [
                local rnamekey = std.splitLimit(rname, ':', 1);
                alertpatching.patchRule(
                  rules[group_name][rname] {
                    // transform source key into "alert: alertname" or
                    // "record: recordname"
                    [rnamekey[0]]: rnamekey[1],
                  },
                  patches={},
                  patchName=false,
                )
                for rname in std.objectFields(rules[group_name])
                if rules[group_name][rname] != null
              ],
            }
            for group_name in std.objectFields(rules)
            if rules[group_name] != null
          ]
        ),
      },
    },
}
