local cm = import 'lib/cert-manager.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local prom = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_monitoring;

local nsName = 'syn-monitoring-openshift4-monitoring';

local promInstance =
  if params.independent_monitoring.instance != null then
    params.independent_monitoring.instance
  else
    inv.parameters.prometheus.defaultInstance;

local serviceMonitor = function(name)
  prom.ServiceMonitor(name) {
    metadata+: {
      namespace: nsName,
    },
    spec: {
      endpoints: [
        {
          bearerTokenSecret: {
            key: '',
          },
          interval: '30s',
          port: 'metrics',
          scheme: 'https',
          tlsConfig: {
            caFile: '/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt',
            certFile: '/etc/prometheus/secrets/ocp-metric-client-certs-monitoring/tls.crt',
            keyFile: '/etc/prometheus/secrets/ocp-metric-client-certs-monitoring/tls.key',
            serverName: 'alertmanager-main.openshift-monitoring.svc',
          },
        },
      ],
      namespaceSelector: {
        matchNames: [
          params.namespace,
        ],
      },
      selector: {
        matchLabels: {
          'app.kubernetes.io/component': 'alert-router',
          'app.kubernetes.io/instance': 'main',
          'app.kubernetes.io/name': 'alertmanager',
          'app.kubernetes.io/part-of': 'openshift-monitoring',
        },
      },
    },
  };

if params.independent_monitoring.enabled && std.member(inv.applications, 'prometheus') then
  [
    prom.RegisterNamespace(
      kube.Namespace(nsName),
      instance=promInstance
    ),
    serviceMonitor('alertmanager-main'),
  ]
else
  std.trace(
    'Monitoring disabled or component `prometheus` not present, '
    + 'not deploying ServiceMonitors',
    []
  )
