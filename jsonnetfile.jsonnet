{
  version: 1,
  dependencies: std.prune([
    {
      source: {
        git: {
          remote: 'https://github.com/projectsyn/jsonnet-libs',
          subdir: '',
        },
      },
      version: 'main',
      name: 'syn',
    },
    {
      source: {
        git: {
          remote: 'https://github.com/openshift/cluster-monitoring-operator',
          subdir: 'jsonnet',
        },
      },
      version: std.extVar('cmo_version'),
      name: 'cluster-monitoring-operator',
    },
    if std.extVar('kube_state_metrics_version') != null && std.extVar('kube_state_metrics_version') != '' then
      {
        source: {
          git: {
            remote: 'https://github.com/kubernetes/kube-state-metrics',
            subdir: 'jsonnet',
          },
        },
        version: std.extVar('kube_state_metrics_version'),
        name: 'kube-state-metrics',
      },
    if std.extVar('etcd_version') != '' then
      {
        source: {
          git: {
            remote: 'https://github.com/openshift/cluster-etcd-operator',
            subdir: 'jsonnet',
          },
        },
        version: std.extVar('etcd_version'),
        name: 'cluster-etcd-operator',
      },
  ]),
  legacyImports: true,
}
