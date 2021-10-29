{
  version: 1,
  dependencies: [
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
  ],
  legacyImports: true,
}
