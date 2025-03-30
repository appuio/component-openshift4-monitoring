// main template for openshift4-monitoring
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;
local hasCilium = std.member(inv.applications, 'cilium');

// Policies

local policies = [
  kube.NetworkPolicy('alertmanager-allow-web') {
    spec: {
      podSelector: {
        matchLabels: {
          'app.kubernetes.io/name': 'alertmanager',
        },
      },
      policyTypes: [
        'Ingress',
      ],
      ingress: [
        {
          ports: [
            {
              protocol: 'TCP',
              port: 9092,
            },
            {
              protocol: 'TCP',
              port: 9093,
            },
            {
              protocol: 'TCP',
              port: 9095,
            },
            {
              protocol: 'TCP',
              port: 9097,
            },
          ],
          from: [
            {
              namespaceSelector: {},
            },
          ],
        },
      ],
    },
  },
  kube.NetworkPolicy('allow-same-namespace') {
    spec: {
      ingress: [
        {
          from: [
            {
              podSelector: {},
            },
          ],
        },
      ],
      policyTypes: [
        'Ingress',
      ],
      podSelector: {},
    },
  },
  kube.NetworkPolicy('allow-non-alertmanager') {
    spec: {
      // from https://kubernetes.io/docs/concepts/services-networking/network-policies/#allow-all-ingress-traffic
      ingress: [ {} ],
      policyTypes: [
        'Ingress',
      ],
      podSelector: {
        matchExpressions: [
          {
            key: 'app.kubernetes.io/name',
            operator: 'NotIn',
            values: [
              'alertmanager',
            ],
          },
        ],
      },
    },
  },
] + if hasCilium then [
  // allow all traffic from the cluster nodes, so that the HAproxy ingress can
  // do healthchecks for routes in the openshift-monitoring namespace.
  {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      annotations: {
        'syn.tools/description': |||
          Note that this policy isn't named allow-from-cluster-nodes, even
          though its content is identical to ensure that Espejo doesn't delete
          the policy.
        |||,
      },
      name: 'allow-from-cluster-nodes-custom',
    },
    spec: {
      endpointSelector: {},
      ingress: [
        {
          fromEntities: [
            'host',
            'remote-node',
          ],
        },
      ],
    },
  },
] else [];

// Manifests

local clusterMonitoring = std.map(function(p) com.namespaced('openshift-monitoring', p), policies);
local userWorkload = std.map(function(p) com.namespaced('openshift-user-workload-monitoring', p), policies);

local clusterAlertmanagerIsolationEnabled =
  if std.objectHas(params, 'enableAlertmanagerIsolationNetworkPolicy') then
    std.trace('Parameter `enableAlertmanagerIsolationNetworkPolicy` is deprecated, please use `components.clusterMonitoring.alertmanagerIsolationEnabled`.', params.enableAlertmanagerIsolationNetworkPolicy)
  else
    params.components.clusterMonitoring.alertmanagerIsolationEnabled;

local userWorkloadAlertmanagerIsolationEnabled =
  if std.objectHas(params, 'enableUserWorkloadAlertmanagerIsolationNetworkPolicy') then
    std.trace('Parameter `enableUserWorkloadAlertmanagerIsolationNetworkPolicy` is deprecated, please use `components.userWorkloadMonitoring.alertmanagerIsolationEnabled`.', params.enableUserWorkloadAlertmanagerIsolationNetworkPolicy)
  else
    params.components.userWorkloadMonitoring.alertmanagerIsolationEnabled;

// Define outputs below
{
  [if clusterAlertmanagerIsolationEnabled then '30_netpol_cluster_monitoring']: clusterMonitoring,
  [if userWorkloadAlertmanagerIsolationEnabled then '30_netpol_user_workload']: userWorkload,
}
