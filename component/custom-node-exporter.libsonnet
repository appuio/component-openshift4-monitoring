local kube = import 'kube-ssa-compat.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local nodeExporter = import 'github.com/openshift/cluster-monitoring-operator/jsonnet/components/node-exporter.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Disable all collectors by default. Note that this list may need to be
// updated manually if a new node-exporter release introduces additional
// collectors.
local neDefaultArgs = [
  '--no-collector.arp',
  '--no-collector.bcache',
  '--no-collector.bonding',
  '--no-collector.btrfs',
  '--no-collector.buddyinfo',
  '--no-collector.cgroups',
  '--no-collector.conntrack',
  '--no-collector.cpu',
  '--no-collector.cpufreq',
  '--no-collector.diskstats',
  '--no-collector.dmi',
  '--no-collector.drbd',
  '--no-collector.drm',
  '--no-collector.edac',
  '--no-collector.entropy',
  '--no-collector.ethtool',
  '--no-collector.fibrechannel',
  '--no-collector.filefd',
  '--no-collector.filesystem',
  '--no-collector.hwmon',
  '--no-collector.infiniband',
  '--no-collector.interrupts',
  '--no-collector.ipvs',
  '--no-collector.ksmd',
  '--no-collector.lnstat',
  '--no-collector.loadavg',
  '--no-collector.logind',
  '--no-collector.mdadm',
  '--no-collector.meminfo',
  '--no-collector.meminfo_numa',
  '--no-collector.mountstats',
  '--no-collector.netclass',
  '--no-collector.netdev',
  '--no-collector.netstat',
  '--no-collector.network_route',
  '--no-collector.nfs',
  '--no-collector.nfsd',
  '--no-collector.ntp',
  '--no-collector.nvme',
  '--no-collector.os',
  '--no-collector.perf',
  '--no-collector.powersupplyclass',
  '--no-collector.pressure',
  '--no-collector.processes',
  '--no-collector.rapl',
  '--no-collector.schedstat',
  '--no-collector.selinux',
  '--no-collector.slabinfo',
  '--no-collector.sockstat',
  '--no-collector.softirqs',
  '--no-collector.softnet',
  '--no-collector.stat',
  '--no-collector.supervisord',
  '--no-collector.sysctl',
  '--no-collector.systemd',
  '--no-collector.tapestats',
  '--no-collector.tcpstat',
  '--no-collector.textfile',
  '--no-collector.thermal_zone',
  '--no-collector.time',
  '--no-collector.timex',
  '--no-collector.udp_queues',
  '--no-collector.uname',
  '--no-collector.vmstat',
  '--no-collector.watchdog',
  '--no-collector.wifi',
  '--no-collector.xfs',
  '--no-collector.zfs',
  '--no-collector.zoneinfo',
];

local containsStr(pat, str) = std.length(std.findSubstr(pat, str)) > 0;

local enabledCollectors =
  com.renderArray(params.customNodeExporter.collectors);

local skipDefaultArg(a) = std.foldl(
  function(skip, c) skip || containsStr(c, a),
  enabledCollectors,
  false
);

// generate command line args to enable collectors that are requested
local neCollectorArgs = [
  '--collector.%s' % c
  for c in enabledCollectors
];

local config = {
  commonLabels: {
    'app.kubernetes.io/part-of': 'openshift4-monitoring',
  },
  name: 'appuio-node-exporter',
  namespace: params.namespace,
  version: params.images.node_exporter.tag,
  port: 9199,
  image: '%(registry)s/%(repository)s:%(tag)s' % params.images.node_exporter,
  kubeRbacProxyImage: '%(registry)s/%(repository)s:%(tag)s' % params.images.kube_rbac_proxy,
  ignoredNetworkDevices:: '^.*$',
};

local ne = nodeExporter(config) {
  // customize node-exporter args. We disable all collectors by default, and
  // only enable the ones requested via component parameters.
  daemonset+: {
    spec+: {
      template+: {
        spec+: {
          containers: std.map(
            function(c)
              if c.name == 'appuio-node-exporter' then
                c {
                  args: [
                    a
                    for a in c.args
                    if !containsStr('collector', a)
                  ] + [
                    // only add the disable args for collectors that the user
                    // hasn't requested, since node-exporter doesn't support
                    // passing a disable and enable flag for the same collector.
                    a
                    for a in neDefaultArgs
                    if !skipDefaultArg(a)
                  ] + neCollectorArgs + params.customNodeExporter.args,
                  // fixup `date` call to use busybox compatible option
                  command: std.map(
                    function(cmd)
                      std.strReplace(cmd, '--iso-8601=seconds', '-Iseconds'),
                    c.command
                  ),
                }
              else
                c,
            super.containers
          ),
          // Fixup service-ca issued certificate secret name
          volumes: std.map(
            function(v) if v.name == 'node-exporter-tls' then
              v {
                secret: {
                  secretName: 'appuio-node-exporter-tls',
                },
              }
            else
              v,
            super.volumes
          ),
        },
      },
    },
  },
  // Fixup the secret name to use for the service-ca issued cert
  service+: {
    metadata+: {
      annotations+: {
        'service.beta.openshift.io/serving-cert-secret-name': 'appuio-node-exporter-tls',
      },
    },
  },
  // patch the service monitor to validate the TLS certificate and configure
  // user-provided custom metricRelabelings.
  serviceMonitor+: {
    spec+: {
      endpoints: std.map(
        function(ep) ep {
          metricRelabelings: params.customNodeExporter.metricRelabelings,
          tlsConfig: {
            ca: {},
            caFile: '/etc/prometheus/configmaps/serving-certs-ca-bundle/service-ca.crt',
            cert: {},
            certFile: '/etc/prometheus/secrets/metrics-client-certs/tls.crt',
            keyFile: '/etc/prometheus/secrets/metrics-client-certs/tls.key',
            serverName: 'appuio-node-exporter.openshift-monitoring.svc',
          },
        },
        super.endpoints
      ),
    },
  },

  // we don't need the networkpolicy
  networkPolicy:: {},
  // we don't need the servicemonitor generated by
  // openshift-cluster-monitoring, we customize the one generated
  // by the kube-prometheus Jsonnet.
  minimalServiceMonitor:: {},
  // we don't need a copy of the SCC for our node-exporter, we can use the one
  // generated by the cluster-monitoring-operator.
  securityContextConstraints:: {},
  // we don't need the default node-exporter prometheus rules
  mixin:: {},
  prometheusRule:: {},
};

std.objectValues(ne)
