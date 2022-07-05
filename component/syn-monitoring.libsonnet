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
  if params.syn_monitoring.instance != null then
    params.syn_monitoring.instance
  else
    inv.parameters.prometheus.defaultInstance;

local endpointConfiguration = function(serverName) {
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
    serverName: serverName,
  },
};

local alertmanagerServiceMonitor = prom.ServiceMonitor('alertmanager-main') {
  metadata+: {
    namespace: nsName,
  },
  spec: {
    endpoints: [
      endpointConfiguration('alertmanager-main.openshift-monitoring.svc') {
        metricRelabelings: [
          {
            action: 'keep',
            sourceLabels: [
              '__name__',
            ],
            regex: 'alertmanager_.*',
          },
        ],
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

local prometheusServiceMonitor = prom.ServiceMonitor('prometheus-k8s') {
  metadata+: {
    namespace: nsName,
  },
  spec: {
    endpoints: [
      endpointConfiguration('prometheus-k8s.openshift-monitoring.svc') {
        metricRelabelings: [
          {
            action: 'keep',
            sourceLabels: [
              '__name__',
            ],
            regex: 'prometheus_.*',
          },
          {
            action: 'drop',
            sourceLabels: [
              '__name__',
            ],
            regex: std.join('|', [
              'prometheus_(http|rule|target)_.*',
              'prometheus_remote_storage_sent_batch_duration_seconds_bucket',
            ]),
          },
        ],
      },
    ],
    namespaceSelector: {
      matchNames: [
        params.namespace,
      ],
    },
    selector: {
      matchLabels: {
        'app.kubernetes.io/component': 'prometheus',
        'app.kubernetes.io/instance': 'k8s',
        'app.kubernetes.io/name': 'prometheus',
        'app.kubernetes.io/part-of': 'openshift-monitoring',
      },
    },
  },
};

if params.syn_monitoring.enabled && std.member(inv.applications, 'prometheus') then
  [
    prom.RegisterNamespace(
      kube.Namespace(nsName),
      instance=promInstance
    ),
    alertmanagerServiceMonitor,
    prometheusServiceMonitor,
  ]
else
  std.trace(
    'Monitoring disabled or component `prometheus` not present, '
    + 'not deploying ServiceMonitors',
    []
  )
