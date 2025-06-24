local cmo_version = std.extVar('cmo_version');
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
    if cmo_version != '' then {
      name: 'cluster-monitoring-operator',
      source: {
        git: {
          remote: 'https://github.com/openshift/cluster-monitoring-operator',
          subdir: 'jsonnet',
        },
      },
      version: std.extVar('cmo_version'),
    },
  ]),
  legacyImports: true,
}
