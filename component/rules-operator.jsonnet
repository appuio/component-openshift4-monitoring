local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local oplib = import 'lib/openshift4-monitoring-operator-rules.libsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local global_name = 'openshift4-monitoring-rules';
local global_namespace = inv.parameters.espejote.namespace;

local mr_namespaces = com.renderArray(
  params.operatorRuleNamespaces
  + [ 'openshift-monitoring' ]
  + if params.enableUserWorkload then [ 'openshift-user-workload-monitoring' ] else []
);


// --- Global Libraries --------------------------------------------------------

local roleGlobal = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: {
    name: global_name,
    namespace: global_namespace,
  },
  rules: [
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      resourceNames: [ global_name ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local roleBindingGlobal = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: global_name,
    namespace: global_namespace,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: roleGlobal.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: global_name,
      namespace: ns,
    }
    for ns in mr_namespaces
  ],
};

local jsonnetLibraryGlobal = esp.jsonnetLibrary(global_name, global_namespace) {
  spec: {
    data: {
      'config_v1.json': std.manifestJson({
        ignoreGroups: params.alerts.ignoreGroups,
        ignoreNames: params.alerts.ignoreNames,
        ignoreWarnings: params.alerts.ignoreWarnings,
        ignoreUserWorkload: params.alerts.ignoreUserWorkload,
        customAnnotations: params.alerts.customAnnotations,
        patchRules: params.alerts.patchRules,
        teamLabel: syn_teams.teamForApplication(inv.parameters._instance),
        includeNamespaces: params.alerts.includeNamespaces,
        excludeNamespaces: params.alerts.excludeNamespaces,
      }),
      'renderer_v1.libsonnet': importstr 'espejote-templates/rules-renderer-v1.libsonnet',
    },
  },
};


// --- Component Specific ------------------------------------------------------

local jsonnetLibrary(ns) = esp.jsonnetLibrary(global_name, ns) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        ignoreNames: [ 'AlertmanagerConfigInconsistent' ],
      }),
    },
  },
};


// Define outputs below
{
  '40_oprules_global': [
    roleGlobal,
    roleBindingGlobal,
    jsonnetLibraryGlobal,
  ],
} + {
  ['40_oprules_%s' % std.strReplace(ns, 'openshift-', '')]: [
    oplib.serviceAccount(ns),
    oplib.role(ns),
    oplib.roleBinding(ns),
    oplib.managedResourceV1(ns),
    jsonnetLibrary(ns),
  ]
  for ns in mr_namespaces
}
