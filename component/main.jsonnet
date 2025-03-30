// main template for openshift4-monitoring
local config = import 'config.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local po = import 'lib/patch-operator.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Namespaces

local ns =
  if params.namespace != 'openshift-monitoring' then
    error 'Component openshift4-monitoring does not support values for parameter `namespace` other than "openshift-monitoring".'
  else
    params.namespace;

local ns_patch =
  po.Patch(
    kube.Namespace(ns),
    {
      metadata: {
        labels: {
          'network.openshift.io/policy-group': 'monitoring',
        } + if std.member(inv.applications, 'networkpolicy') then {
          [inv.parameters.networkpolicy.labels.noDefaults]: 'true',
          [inv.parameters.networkpolicy.labels.purgeDefaults]: 'true',
        } else {},
      },
    }
  );

// RBAC

local rbacAggregatedClusterRole = kube.ClusterRole('syn-openshift4-monitoring-cluster-reader') {
  metadata+: {
    labels+: {
      'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
    },
  },
  rules: [
    {
      apiGroups: [ 'monitoring.coreos.com' ],
      resources: [ '*' ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
  ],
};

/*
* Allows Prometheus auto-discovery.
* Adds the recommended permissions from https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/rbac.md#prometheus-rbac
*/
local rbacDiscoveryRole = kube.ClusterRole('syn-prometheus-auto-discovery') {
  metadata+: {
    annotations+: {
      syn_component: inv.parameters._instance,
    },
  },
  rules: [
    {
      apiGroups: [
        '',
      ],
      resources: [
        'pods',
        'services',
        'endpoints',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
    {
      apiGroups: [
        'networking.k8s.io',
      ],
      resources: [
        'ingresses',
      ],
      verbs: [
        'get',
        'list',
        'watch',
      ],
    },
  ],
};

local rbacDiscoveryBinding = kube.ClusterRoleBinding('syn-prometheus-auto-discovery') {
  metadata+: {
    annotations+: {
      syn_component: inv.parameters._instance,
    },
  },
  roleRef_: rbacDiscoveryRole,
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'prometheus-k8s',
      namespace: 'openshift-monitoring',
    },
  ],
};

// Define outputs below
{
  '00_namespace_labels': ns_patch,
  '10_rbac_aggregated': rbacAggregatedClusterRole,
  '10_rbac_discovery': [ rbacDiscoveryRole, rbacDiscoveryBinding ],
  '10_secrets': com.generateResources(params.secrets, kube.Secret),
}
+ (import 'config_cluster.libsonnet')
+ (import 'config_alertmanager.libsonnet')
+ (import 'networkpolicy.libsonnet')
+ (import 'rules.libsonnet')
+ (import 'rules_capacity.libsonnet')
+ (import 'silences.libsonnet')
+ (import 'cronjobs.libsonnet')
+ (import 'node_exporter.libsonnet')
