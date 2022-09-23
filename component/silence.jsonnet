local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local namespace = {
  metadata+: {
    namespace: params.namespace,
  },
};

local cm = kube.ConfigMap('silence') + namespace {
  data: {
    silence: importstr './scripts/silence.sh',
  },
};

local cronJob = kube.CronJob('silence') + namespace {
  spec+: {
    schedule: params.silence.schedule,
    failedJobsHistoryLimit: params.silence.jobHistoryLimit.failed,
    successfulJobsHistoryLimit: params.silence.jobHistoryLimit.successful,
    jobTemplate+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: params.silence.nodeSelector,
            restartPolicy: 'Never',
            serviceAccountName: params.silence.serviceAccountName,
            containers_+: {
              silence: kube.Container('silence') {
                image: params.images.oc.image + ':' + params.images.oc.tag,
                command: [ '/usr/local/bin/silence' ],
                volumeMounts_+: {
                  scripts: {
                    mountPath: '/usr/local/bin/',
                    readOnly: true,
                  },
                  'ca-bundle': {
                    mountPath: '/etc/ssl/certs/serving-certs/',
                    readOnly: true,
                  },
                },
              },
            },
            volumes_+: {
              scripts: {
                configMap: {
                  name: 'silence',
                  defaultMode: std.parseOctal('0550'),
                },
              },
              'ca-bundle': {
                configMap: {
                  defaultMode: std.parseOctal('0440'),
                  name: params.silence.servingCertsCABundleName,
                },
              },
            },
          },
        },
      },
    },
  },
};

[
  cm,
  cronJob,
]
