local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.control_api;

local defaultAnnotations = {
  syn_component: inv.parameters._instance,
};

/*
* Allows discovery of services, pods, and endpoints for prometheus auto-discovery
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
      namespace: 'openshift-monitoring',
    },
  ],
};


[ discoveryRole, discoveryRoleBinding ]
