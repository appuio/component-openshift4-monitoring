/**
 * \file openshift4-monitoring-operator-rules.libsonnet
 * \brief Helpers to create ManagedResource CRs for managing operator PrometheusRules.
 */

local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';

local inv = com.inventory();
local params = inv.parameters.openshift4_monitoring;

local global_name = 'openshift4-monitoring-rules';
local global_namespace = inv.parameters.espejote.namespace;

local esp_gv = 'espejote.io/v1alpha1';


/**
 * \brief create a ServiceAccount for managing operator PrometheusRules.
 *
 * \arg ns
 *        The namespace to deploy the ServiceAccount to.
 * \returns
 *        A ServiceAccount CR for managing operator PrometheusRules.
 */
local serviceAccount(ns) = {
  apiVersion: 'v1',
  kind: 'ServiceAccount',
  metadata: {
    name: global_name,
    namespace: ns,
  },
};

/**
 * \brief create a RoleBinding for managing operator PrometheusRules.
 *
 * \arg ns
 *        The namespace to deploy the RoleBinding to.
 * \returns
 *        A RoleBinding CR for managing operator PrometheusRules.
 */
local roleBinding(ns) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: global_name,
    namespace: ns,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'monitoring-rules-edit',
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount(ns).metadata.name,
    },
  ],
};

/**
 * \brief create a minimal ManagedResource for managing operator PrometheusRules.
 *
 * \arg ns
 *        The namespace to deploy the ManagedResource to.
 * \returns
 *        A ManagedResource CR for managing operator PrometheusRules.
 */
local managedResource(ns) = esp.managedResource(global_name, ns) {
  spec: {
    serviceAccountRef: { name: serviceAccount(ns).metadata.name },
    context: [
      {
        name: 'op_rules',
        resource: {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'PrometheusRule',
          labelSelector: {
            // Only match rules that are not created by espejote: 'espejote.io/created-by'
            // and are not marked to be ignored: 'espejote.io/ignore'
            matchExpressions: [
              {
                key: 'espejote.io/created-by',
                operator: 'DoesNotExist',
              },
              {
                key: 'espejote.io/ignore',
                operator: 'DoesNotExist',
              },
            ],
          },
          namespace: ns,
        },
      },
    ],
    triggers: [
      {
        name: 'op_rules',
        watchContextResource: {
          name: 'op_rules',
        },
      },
      //   {
      //     name: 'jslib_global',
      //     watchResource: {
      //       apiVersion: esp_gv,
      //       kind: 'JsonnetLibrary',
      //       name: global_name,
      //       namespace: global_namespace,
      //     },
      //   },
      //   {
      //     name: 'jslib_component',
      //     watchResource: {
      //       apiVersion: jsonnetLibrary(ns).apiVersion,
      //       kind: jsonnetLibrary(ns).kind,
      //       name: jsonnetLibrary(ns).metadata.name,
      //       namespace: jsonnetLibrary(ns).metadata.namespace,
      //     },
      //   },
    ],
    template: |||
      local esp = import 'espejote.libsonnet';

      local renderer = import 'lib/openshift4-monitoring-rules/renderer_v1.libsonnet';
      local configGlobal = import 'lib/openshift4-monitoring-rules/config_v1.json';
      local configComponent = import 'openshift4-monitoring-rules/config.json';

      local opRules = esp.context().op_rules;

      [
        renderer.parse(or, configGlobal, configComponent),
        for or in opRules
      ]
    |||,
  },
};

{
  serviceAccount: serviceAccount,
  roleBinding: roleBinding,
  managedResourceV1: managedResource,
}
