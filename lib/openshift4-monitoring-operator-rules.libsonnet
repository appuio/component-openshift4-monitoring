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
 * \brief create a Role for managing operator PrometheusRules.
 *
 * \arg ns
 *        The namespace to deploy the RoleBinding to.
 * \returns
 *        A Role CR for managing operator PrometheusRules.
 */
local role(ns) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: {
    name: global_name,
    namespace: ns,
  },
  rules: [
    {
      apiGroups: [ 'monitoring.coreos.com' ],
      resources: [ 'prometheusrules' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      resourceNames: [ global_name ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
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
    kind: 'Role',
    name: global_name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount(ns).metadata.name,
    },
  ],
};

/**
 * \brief create a RoleBinding for accessomg the global JsonnetLibrary.
 *
 * \arg ns
 *        The namespace where the ManagedResource is deployed to.
 * \returns
 *        A RoleBinding CR for accessing the global JsonnetLibrary.
 */
local roleBindingGlobal(ns) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: '%s-%s' % [ global_name, ns ],
    namespace: global_namespace,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: global_name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount(ns).metadata.name,
      namespace: ns,
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
      {
        name: 'generated_rules',
        watchResource: {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'PrometheusRule',
          labelSelector: {
            // Only match rules that are created by espejote: 'espejote.io/created-by=openshift4-monitoring-rules'
            matchExpressions: [
              {
                key: 'espejote.io/created-by',
                operator: 'In',
                values: [ 'openshift4-monitoring-rules' ],
              },
            ],
          },
        },
      },
      {
        name: 'jslib_global',
        watchResource: {
          apiVersion: esp_gv,
          kind: 'JsonnetLibrary',
          name: global_name,
          namespace: global_namespace,
        },
      },
      {
        name: 'jslib_component',
        watchResource: {
          apiVersion: esp_gv,
          kind: 'JsonnetLibrary',
          name: global_name,
          namespace: ns,
        },
      },
    ],
    template: |||
      local esp = import 'espejote.libsonnet';

      local renderer = import 'lib/openshift4-monitoring-rules/renderer_v1.libsonnet';
      local configGlobal = import 'lib/openshift4-monitoring-rules/config_v1.json';
      local configComponent = import 'openshift4-monitoring-rules/config.json';

      local opRules = esp.context().op_rules;
      local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';

      if std.member([ 'op_rules', 'generated_rules' ], esp.triggerName) then
        // if the trigger is 'op_rules' or 'generated_rules', render single op_rule
        local trigger = esp.triggerData();
        local or = if esp.triggerName == 'op_rules' then
          trigger.resource
        else
          local cand = std.filter(function(r) r.metadata.name == trigger.resource.metadata.ownerReferences[0].name, opRules);
          if std.length(cand) > 0 then cand[0];

        if trigger != null && !inDelete(trigger) && or != null && !inDelete(or) then [
          renderer.process(or, configGlobal, configComponent)
        ]
      else [
        // if the trigger is not 'op_rules' or 'generated_rules', render all op_rules
        renderer.process(or, configGlobal, configComponent),
        for or in opRules
        if !inDelete(or)
      ]
    |||,
  },
};

{
  serviceAccount: serviceAccount,
  role: role,
  roleBinding: roleBinding,
  roleBindingGlobal: roleBindingGlobal,
  managedResourceV1: managedResource,
}
