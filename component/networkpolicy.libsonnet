local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local cilium_cluster = std.member(inv.applications, 'cilium');

[
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
] + if cilium_cluster then [
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
] else []
