local kube = import 'kube-ssa-compat.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_monitoring;

local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};

/*
* Allows Prometheus auto-discovery.
* Adds the recommended permissions from https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/rbac.md#prometheus-rbac
*/
local discoveryRole = kube.ClusterRole('syn-prometheus-auto-discovery') {
  metadata+: {
    annotations+: defaultAnnotations,
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

local discoveryRoleBinding = kube.ClusterRoleBinding('syn-prometheus-auto-discovery') {
  metadata+: {
    annotations+: defaultAnnotations,
  },
  roleRef_: discoveryRole,
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'prometheus-k8s',
      namespace: params.namespace,
    },
  ],
};


[ discoveryRole, discoveryRoleBinding ]
