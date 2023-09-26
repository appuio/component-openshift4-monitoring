local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prom.libsonnet';

local inv = kap.inventory();
local params = inv.parameters;

local adParams = params.openshift4_monitoring.alertManagerAutoDiscovery;

local nullReceiver = '__component_openshift4_monitoring_null';

// appKeys returns the (aliased) application name and if aliased the original name in the second position.
// The application name is translated from kebab-case to snake_case, except if the second parameter is set to true.
local appKeys = function(name, raw=false)
  local normalized = function(name) if raw then name else std.strReplace(name, '-', '_');
  // can be simplified with jsonnet > 0.19 which would support ' as ' as the substring
  local parts = std.split(name, ' ');
  if std.length(parts) == 1 then
    [ normalized(parts[0]) ]
  else if std.length(parts) == 3 && parts[1] == 'as' then
    [ normalized(parts[2]), normalized(parts[0]) ]
  else
    error 'invalid application name `%s`' % name;

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

  local ks = appKeys(app);
  local aliased = f(ks[0]);
  if aliased != null then
    aliased
  else if std.length(ks) == 2 then
    f(ks[1]);


local ownerOrFallbackTeam =
  if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'owner') then
    params.syn.owner
  else
    params.openshift4_monitoring.fallback_team;

// teamsForApplication returns the teams for the given application.
// It does so by looking at the top level syn parameter.
// The syn parameter should look roughly like this.
//
//   syn:
//     owner: clumsy-donkeys
//     teams:
//       chubby-cockroaches:
//         instances:
//           - superb-visualization
//       lovable-lizards:
//         instances:
//           - apartment-cats
//
// The application is first looked up in the instances of the teams, if no team is found, owner is used as fallback.
local teamsForApplication = function(app)
  local lookup = function(app)
    if std.objectHas(params, 'syn') && std.objectHas(params.syn, 'teams') then
      local teams = params.syn.teams;
      std.foldl(
        function(prev, team)
          if std.objectHas(teams, team) && std.objectHas(teams[team], 'instances') && std.member(teams[team].instances, app) then
            prev + [ team ]
          else
            prev,
        std.objectFields(teams),
        [],
      );

  local teams = std.prune(std.map(lookup, appKeys(app, true)));

  if std.length(teams) > 0 then
    teams[0]
  else
    [ ownerOrFallbackTeam ];

// teamToNS is a map from a team to namespaces.
local teamToNS = std.foldl(
  function(prev, app)
    local tms = teamsForApplication(app);
    std.foldl(
      function(prev, tm) prev { [tm]+: [ discoverNS(app) ] }, tms, prev
    )
  ,
  inv.applications,
  {}
);

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
  params.openshift4_monitoring.alertManagerConfig {
    receivers+: [ { name: nullReceiver } ],
    route+: {
      routes: adParams.prepend_routes + teamBasedRouting + adParams.append_routes + super.routes + if ownerOrFallbackTeam != null then [ {
        receiver: adParams.team_receiver_format % ownerOrFallbackTeam,
      } ] else [ { receiver: nullReceiver } ],
    },
  };

{
  debugConfigMap: kube.ConfigMap('discovery-debug') {
    data: {
      local discoveredNamespaces = std.foldl(function(prev, app) prev { [app]: discoverNS(app) }, inv.applications, {}),
      local discoveredTeams = std.foldl(function(prev, app) prev { [app]: teamsForApplication(app) }, inv.applications, {}),
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
