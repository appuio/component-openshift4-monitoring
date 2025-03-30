// main template for openshift4-monitoring
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters;

// Configuration: Defaults

local _defaultsAlertManager = {
  route: {
    group_wait: '0s',
    group_interval: '5s',
    repeat_interval: '10m',
  },
  inhibit_rules: [
    // Don't send warning or info if a critical is already firing
    {
      target_match_re: {
        severity: 'warning|info',
      },
      source_match: {
        severity: 'critical',
      },
      equal: [
        'namespace',
        'alertname',
      ],
    },
    // Don't send info if a warning is already firing
    {
      target_match_re: {
        severity: 'info',
      },
      source_match: {
        severity: 'warning',
      },
      equal: [
        'namespace',
        'alertname',
      ],
    },
  ],
};

local _defaultsAutoDiscovery = {
  enabled: params.openshift4_monitoring.components.alertManagerAutoDiscovery.enabled,
  debug_config_map: params.openshift4_monitoring.components.alertManagerAutoDiscovery.debugConfigMap,
  team_receiver_format: params.openshift4_monitoring.components.alertManagerAutoDiscovery.teamReceiverFormat,
  additional_alert_matchers: params.openshift4_monitoring.components.alertManagerAutoDiscovery.additionalAlertMatchers,
  prepend_routes: params.openshift4_monitoring.components.alertManagerAutoDiscovery.prependRoutes,
  append_routes: params.openshift4_monitoring.components.alertManagerAutoDiscovery.appendRoutes,
};

// Configuration: Legacy

local _legacyAlertManager = com.makeMergeable(
  if std.objectHas(params.openshift4_monitoring, 'alertManagerConfig') then
    std.trace('Parameter `alertManagerConfig` is deprecated, please use `components.alertManager.config`.', params.openshift4_monitoring.alertManagerConfig)
  else {},
);

local _legacyAutoDiscovery = com.makeMergeable(
  if std.objectHas(params.openshift4_monitoring, 'alertManagerAutoDiscovery') then
    std.trace('Parameter `alertManagerAutoDiscovery` is deprecated, please use `components.alertManagerAutoDiscovery`.', params.openshift4_monitoring.alertManagerAutoDiscovery)
  else {},
);

// Configuration: Final

local configAlertManager = _defaultsAlertManager + com.makeMergeable(params.openshift4_monitoring.components.alertManager.config) + _legacyAlertManager;
local configAutoDiscovery = _defaultsAutoDiscovery + _legacyAutoDiscovery;

// Helpers: AlertManager AutoDiscovery

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
  if aliased != null then
    aliased
  else if std.length(ks) == 2 then
    f(ks[1]);

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
    receiver: configAutoDiscovery.team_receiver_format % k,
    matchers: configAutoDiscovery.additional_alert_matchers + [
      'namespace =~ "%s"' % std.join('|', teamToNS[k]),
    ],
    continue: true,
  },
  std.objectFields(teamToNS)
) + [ {
  // catch all alerts already routed to a team
  receiver: nullReceiver,
  matchers: configAutoDiscovery.additional_alert_matchers + [
    'namespace =~ "%s"' % std.join('|', std.foldl(function(prev, nss) prev + nss, std.objectValues(teamToNS), [])),
  ],
  continue: false,
} ];

// Manifests

local alertManagerDiscovery =
  local routes = std.get(configAlertManager.route, 'routes', []);
  std.prune(configAlertManager) {
    receivers+: [ { name: nullReceiver } ],
    route+: {
      routes: configAutoDiscovery.prepend_routes + teamBasedRouting + configAutoDiscovery.append_routes + routes + if ownerOrFallbackTeam != null then [ {
        receiver: configAutoDiscovery.team_receiver_format % ownerOrFallbackTeam,
      } ] else [ { receiver: nullReceiver } ],
    },
  };

local alertManager = kube.Secret('alertmanager-main') {
  metadata+: {
    namespace: 'openshift-monitoring',
  },
  stringData: {
    'alertmanager.yaml': std.manifestYamlDoc(
      if configAutoDiscovery.enabled then
        alertManagerDiscovery
      else
        // We prune the user-provided config in the alert-discovery
        // implementation. To avoid surprises, we explicitly prune the
        // user-provided config here, if discovery is disabled.
        std.prune(configAlertManager)
    ),
  },
};

local autoDiscoveryDebug = kube.ConfigMap('discovery-debug') {
  metadata+: {
    namespace: 'openshift-monitoring',
  },
  data: {
    local discoveredNamespaces = std.foldl(function(prev, app) prev { [app]: discoverNS(app) }, inv.applications, {}),
    local discoveredTeams = std.foldl(function(prev, app) prev { [app]: syn_teams.teamForApplication(syn_teams.appKeys(app, true)[0]) }, inv.applications, {}),
    applications: std.manifestJsonMinified(inv.applications),
    discovered_namespaces: std.manifestYamlDoc(discoveredNamespaces),
    apps_without_namespaces: std.manifestYamlDoc(std.foldl(function(prev, app) if discoveredNamespaces[app] == null then prev + [ app ] else prev, std.objectFields(discoveredNamespaces), [])),
    discovered_teams: std.manifestYamlDoc(discoveredTeams),
    proposed_routes: std.manifestYamlDoc(teamBasedRouting),
    alertmanager: std.manifestYamlDoc(alertManagerDiscovery),
  },
};

local autoDiscoveryDebugEnabled = configAutoDiscovery.enabled && configAutoDiscovery.debug_config_map;

// Define outputs below
{
  '20_config_alertmanager': alertManager,
  [if autoDiscoveryDebugEnabled then '20_debug_auto_discovery']: autoDiscoveryDebug,
}
