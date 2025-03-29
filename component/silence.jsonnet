local config = import 'config.libsonnet';
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
  local silences = config.silence.silences,
  data: {
    silence: importstr './scripts/silence.sh',
    'silences.json': std.manifestJsonMinified([
      silences[comment] { comment: comment }
      for comment in std.objectFields(silences)
    ]),
  },
};

local cronJob = kube.CronJob('silence') + namespace {
  spec+: {
    schedule: config.silence.schedule,
    failedJobsHistoryLimit: config.silence.jobHistoryLimit.failed,
    successfulJobsHistoryLimit: config.silence.jobHistoryLimit.successful,
    jobTemplate+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: config.silence.nodeSelector,
            restartPolicy: 'Never',
            serviceAccountName: config.silence.serviceAccountName,
            containers_+: {
              silence: kube.Container('silence') {
                image: '%(registry)s/%(repository)s:%(tag)s' % params.images.oc,
                command: [ '/usr/local/bin/silence' ],
                env_+: {
                  SILENCES_JSON: {
                    configMapKeyRef: {
                      name: cm.metadata.name,
                      key: 'silences.json',
                    },
                  },
                },
                volumeMounts_+: {
                  scripts: {
                    mountPath: '/usr/local/bin/silence',
                    subPath: 'silence',
                    readOnly: true,
                  },
                  'ca-bundle': {
                    mountPath: '/etc/ssl/certs/serving-certs/',
                    readOnly: true,
                  },
                  'kube-api-access': {
                    mountPath: '/var/run/secrets/kubernetes.io/serviceaccount',
                    readOnly: true,
                  },
                },
              },
            },
            volumes_+: {
              scripts: {
                configMap: {
                  name: cm.metadata.name,
                  defaultMode: std.parseOctal('0550'),
                },
              },
              'ca-bundle': {
                configMap: {
                  defaultMode: std.parseOctal('0440'),
                  name: config.silence.servingCertsCABundleName,
                },
              },
              // we need to explictly configure the projected volume as the
              // 'prometheus-k8s' ServiceAccount has
              // `automountServiceAccountToken=false` on fresh OCP 4.11
              // setups.
              // NOTE: This doesn't break on older/upgraded clusters but
              // having the explict projected volume simply disables the token
              // automount.
              'kube-api-access': {
                projected: {
                  defaultMode: 420,
                  sources: [
                    {
                      serviceAccountToken: {
                        expirationSeconds: 3607,
                        path: 'token',
                      },
                    },
                  ],
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
