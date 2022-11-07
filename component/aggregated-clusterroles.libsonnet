local kube = import 'lib/kube.libjsonnet';

local cluster_reader =
  kube.ClusterRole('syn-openshift4-monitoring-cluster-reader') {
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

[
  cluster_reader,
]
