/**
 * \file prom.libsonnet
 * \brief Helpers to create Prometheus Operator CRs.
 *        API reference: https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/api.md
 */

local com = import 'lib/commodore.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local alertpatching = import 'lib/alert-patching.libsonnet';

local inv = com.inventory();

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
  * \brief Returns an array with the (aliased) application name and if aliased the original name in the second position.
  *
  * The application name is translated from kebab-case to snake_case, except if the second parameter is set to true.
  *
  * \arg name
  *    The application name. Can be `name` or `name as alias`.
  * \arg raw
  *    If set to true, the application name is not translated from kebab-case to snake_case.
  * \return
  *    An array with the (aliased) application name and if aliased the original name in the second position.
  */
  appKeys: function(name, raw=false)
    local normalized = function(name) if raw then name else std.strReplace(name, '-', '_');
    // can be simplified with jsonnet > 0.19 which would support ' as ' as the substring
    local parts = std.split(name, ' ');
    if std.length(parts) == 1 then
      [ normalized(parts[0]) ]
    else if std.length(parts) == 3 && parts[1] == 'as' then
      [ normalized(parts[2]), normalized(parts[0]) ]
    else
      error 'invalid application name `%s`' % name,

  /**
  * \brief Returns the team for the given application or null.
  *
  * It does so by looking at the top level syn parameter.
  * The syn parameter should look roughly like this.
  *
  *   syn:
  *     owner: clumsy-donkeys
  *     teams:
  *       chubby-cockroaches:
  *         instances:
  *           - superb-visualization
  *       lovable-lizards:
  *         instances:
  *           - apartment-cats
  *
  * The application is first looked up in the instances of the teams, if no team is found, owner is used as fallback.
  * An error is thrown if the application is found belonging to multiple teams.
  *
  * \arg app
  *    The application name. Can be the merged `inventory().params._instance` or an (aliased) application name.
  * \return
  *    The team name or `null` if no team is found.
  */
  teamForApplication: function(app)
    local params = inv.parameters;
    local lookup = function(app)
      if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'teams') then
        local teams = params.syn.teams;
        local teamsForApp = std.foldl(
          function(prev, team)
            if std.objectHas(teams, team) && std.objectHas(teams[team], 'instances') && std.member(com.renderArray(teams[team].instances), app) then
              prev + [ team ]
            else
              prev,
          std.objectFields(teams),
          [],
        );
        if std.length(teamsForApp) == 0 then
          null
        else if std.length(teamsForApp) == 1 then
          teamsForApp[0]
        else
          error 'application `%s` is in multiple teams: %s' % [ app, std.join(', ', teamsForApp) ];

    local teams = std.prune(std.map(lookup, self.appKeys(app, true)));

    if std.length(teams) > 0 then
      teams[0]
    else if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
      params.syn.owner,

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
