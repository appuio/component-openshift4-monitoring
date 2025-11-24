local kube = import 'kube-ssa-compat.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters;

local adParams = params.openshift4_monitoring.alertManagerAutoDiscovery;

local nullReceiver = '__component_openshift4_monitoring_null';

// discoverNS returns the namespace for the given application.
// It looks into the follwing places:
// - params.<app>.namespace
// - params.<app>.namespace.name
// It does respect aliased applications and looks in the instance first and then in the base application.
local discoverNS = function(app)
  local f = function(k)
    if std.objectHas(params, k) then
      local p = params[k];
      if std.objectHas(p, 'namespace') then
        if std.isString(p.namespace) then
          p.namespace
        else if std.isObject(p.namespace) && std.objectHas(p.namespace, 'name') && std.isString(p.namespace.name) then
          p.namespace.name;

  local ks = syn_teams.appKeys(app);
  local aliased = f(ks[0]);
  local ns =
    if aliased != null then
      aliased
    else if std.length(ks) == 2 then
      f(ks[1]);

  // We tend to use `namespace: ${_instance}` for components where we deploy
  // each instance in a separate namespace (e.g. component-vault,
  // component-openshift4-operators). However, because we read the instance
  // namespaces from openshift4-monitoring's parameters, `${_instance}` is
  // resolved to `openshift4-monitoring` and not to the component instance
  // name.
  //
  // We override the discovered namespace here if we discover a namespace that
  // contains `openshift4-monitoring` for any app other than
  // `openshift4-monitoring` itself.
  if
    ns != null &&
    app != 'openshift4-monitoring' &&
    std.length(std.findSubstr('openshift4-monitoring', ns)) > 0
  then
    std.trace(
      'overriding namespace autodiscovery for `%s` (discovered namespace: %s)' % [ app, ns ],
      std.strReplace(ns, 'openshift4-monitoring', std.strReplace(ks[0], '_', '-'))
    )
  else
    ns;

local ownerOrFallbackTeam =
  if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
    params.syn.owner
  else
    params.openshift4_monitoring.fallback_team;

// teamToNS is a map from a team to namespaces.
// The inner `std.prune()` is to drop `null` entries from a list that contains
// a mix of null and non-null entries. The outer `std.prune()` drops teams
// for which we haven't discovered any namespaces from the resulting object.
local teamToNS = std.prune(std.mapWithKey(
  function(_, a) std.uniq(std.sort(std.prune(a))),
  std.foldl(
    function(prev, app)
      local instance = syn_teams.appKeys(app, true)[0];
      local team = syn_teams.teamForApplication(instance);
      prev { [team]+: [ discoverNS(app) ] },
    inv.applications,
    {}
  )
));

// teamBasedRouting contains discovered routes for teams.
// The routes are set up with `continue: true` so we can route to multiple teams.
// The last route catches all alerts already routed to a team.
local teamBasedRouting = std.map(
  function(k) {
    receiver: adParams.team_receiver_format % k,
    matchers: adParams.additional_alert_matchers + [
      'namespace =~ "%s"' % std.join('|', teamToNS[k]),
    ],
    continue: true,
  },
  std.objectFields(teamToNS)
) + [ {
  // catch all alerts already routed to a team
  receiver: nullReceiver,
  matchers: adParams.additional_alert_matchers + [
    'namespace =~ "%s"' % std.join('|', std.foldl(function(prev, nss) prev + nss, std.objectValues(teamToNS), [])),
  ],
  continue: false,
} ];

local alertmanagerConfig =
  local routes = std.get(params.openshift4_monitoring.alertManagerConfig.route, 'routes', []);
  std.prune(params.openshift4_monitoring.alertManagerConfig) {
    receivers+: [ { name: nullReceiver } ],
    route+: {
      routes: adParams.prepend_routes + teamBasedRouting + adParams.append_routes + routes + if ownerOrFallbackTeam != null then [ {
        receiver: adParams.team_receiver_format % ownerOrFallbackTeam,
      } ] else [ { receiver: nullReceiver } ],
    },
  };

{
  debugConfigMap: kube.ConfigMap('discovery-debug') {
    data: {
      local discoveredNamespaces = std.foldl(function(prev, app) prev { [app]: discoverNS(app) }, inv.applications, {}),
      local discoveredTeams = std.foldl(function(prev, app) prev { [app]: syn_teams.teamForApplication(syn_teams.appKeys(app, true)[0]) }, inv.applications, {}),
      applications: std.manifestJsonMinified(inv.applications),
      discovered_namespaces: std.manifestYamlDoc(discoveredNamespaces),
      apps_without_namespaces: std.manifestYamlDoc(std.foldl(function(prev, app) if discoveredNamespaces[app] == null then prev + [ app ] else prev, std.objectFields(discoveredNamespaces), [])),
      discovered_teams: std.manifestYamlDoc(discoveredTeams),
      proposed_routes: std.manifestYamlDoc(teamBasedRouting),
      alertmanager: std.manifestYamlDoc(alertmanagerConfig),
    },
  },
  alertmanagerConfig: alertmanagerConfig,
}
