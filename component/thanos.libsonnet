local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local kyverno = import 'lib/kyverno.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local objStorageSecret =
  kube.Secret('thanos-sidecar-objstorage') {
    metadata+: {
      namespace: params.namespace,
    },
    stringData: {
      'thanos.yaml': std.manifestYamlDoc(params.thanosObjectStorageConfig, quote_keys=false),
    },
  };

local syncJobSecret =
  local objStorageCfg = params.thanosObjectStorageConfig;
  kube.Secret('thanos-objstorage-mc-config') {
    metadata+: {
      namespace: params.namespace,
      annotations+: {
        'argocd.argoproj.io/sync-wave': '-10',
      },
    },
    stringData: {
      'mc-config.json': std.manifestJson(
        {
          version: '10',
          aliases: {
            s3: {
              url: 'https://%s' % [ objStorageCfg.config.endpoint ],
              accessKey: objStorageCfg.config.access_key,
              secretKey: objStorageCfg.config.secret_key,
              api: 's3v4',
              path: 'auto',
            },
          },
        }
      ),
    },
  };

local ensureBucketSyncJob = kube.Job('ensure-thanos-objstorage-bucket') {
  metadata+: {
    namespace: params.namespace,
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-10',
      'argocd.argoproj.io/hook': 'Sync',
      'argocd.argoproj.io/hook-delete-policy': 'HookSucceeded',
    },
  },
  spec+: {
    template+: {
      spec+: {
        containers_: {
          ensure_bucket: kube.Container('ensure-bucket') {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.mc,
            args: [
              '--config-dir',
              '/etc/mc',
              'mb',
              's3/%s' % [
                params.thanosObjectStorageConfig.config.bucket,
              ],
            ],
            volumeMounts_: {
              mc: {
                mountPath: '/etc/mc',
              },
              mc_config: {
                mountPath: '/etc/mc/config.json',
                subPath: 'mc-config.json',
              },
            },
          },
        },
        volumes_: {
          mc: {
            emptyDir: {},
          },
          mc_config: {
            secret: {
              secretName: syncJobSecret.metadata.name,
            },
          },
        },
      },
    },
  },
};

local policy = kyverno.Policy('thanos-sidecar-objectstorage') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    rules: [
      {
        name: 'configure-sidecar-objstorage',
        match: {
          any: [
            {
              resources: {
                kinds: [ 'monitoring.coreos.com/v1/Prometheus' ],
                names: [ 'k8s' ],
              },
            },
          ],
        },
        mutate: {
          patchStrategicMerge: {
            spec: {
              thanos: {
                objectStorageConfig: {
                  key: 'thanos.yaml',
                  name: objStorageSecret.metadata.name,
                },
              },
            },
          },
        },
      },
    ],
  },
};

local hasObjStorage = std.length(params.thanosObjectStorageConfig) > 0;

{
  manifests:
    if hasObjStorage then
      {
        [if params.thanosObjectStorageConfig.type == 's3'
        then '11-thanos_objstorage_ensure_bucket']:
          [
            syncJobSecret,
            ensureBucketSyncJob,
          ],
        '11_thanos_objstorage_secret': objStorageSecret,
        '11_thanos_objstorage_policy': policy,
      }
    else
      {},
}
