{
  version: 1,
  dependencies: std.prune([
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
    {
      source: {
        git: {
          remote: 'https://github.com/kubernetes/kube-state-metrics',
          subdir: 'jsonnet',
        },
      },
      version: 'v2.13.0',
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
