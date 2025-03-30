// main template for openshift4-monitoring
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

// Configuration

local _defaultsSilences = {
  schedule: '0 */4 * * *',
  serviceAccountName: 'prometheus-k8s',
  servingCertsCABundleName: 'serving-certs-ca-bundle',
  jobHistoryLimit: {
    failed: 3,
    successful: 3,
  },
  nodeSelector: params.defaultNodeSelector,
  silences: {
    'Silence non syn alerts': {
      matchers: [
        {
          name: 'alertname',
          value: '.+',
          isRegex: true,
        },
        {
          name: 'syn',
          value: '',
          isRegex: false,
        },
      ],
    },
  },
};

local configSilences = _defaultsSilences + com.makeMergeable(params.silence);

// Helpers

local namespace = {
  metadata+: {
    namespace: 'openshift-monitoring',
  },
};

// Manifests

local configMap = kube.ConfigMap('silence') + namespace {
  local silences = configSilences.silences,
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
    schedule: configSilences.schedule,
    failedJobsHistoryLimit: configSilences.jobHistoryLimit.failed,
    successfulJobsHistoryLimit: configSilences.jobHistoryLimit.successful,
    jobTemplate+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: configSilences.nodeSelector,
            restartPolicy: 'Never',
            serviceAccountName: configSilences.serviceAccountName,
            containers_+: {
              silence: kube.Container('silence') {
                image: '%(registry)s/%(repository)s:%(tag)s' % params.images.oc,
                command: [ '/usr/local/bin/silence' ],
                env_+: {
                  SILENCES_JSON: {
                    configMapKeyRef: {
                      name: configMap.metadata.name,
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
                  name: configMap.metadata.name,
                  defaultMode: std.parseOctal('0550'),
                },
              },
              'ca-bundle': {
                configMap: {
                  defaultMode: std.parseOctal('0440'),
                  name: configSilences.servingCertsCABundleName,
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

// Define outputs below
{
  '50_silences': [ configMap, cronJob ],
}
