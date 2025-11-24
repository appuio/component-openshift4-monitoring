local kube = import 'kube-ssa-compat.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local makeCronjob(name, args) =
  local scriptSecret = kube.Secret(name) {
    metadata+: {
      namespace: params.namespace,
    },
    data:: {},
    stringData: {
      'script.sh': args.script,
    },
  };
  local image = if std.objectHas(args, 'image') then
    args.image.image + ':' + args.image.tag else
    params.images.oc.image + ':' + params.images.oc.tag;
  [
    scriptSecret,
    kube.CronJob(name) {
      metadata+: {
        namespace: params.namespace,
      },
      spec+: {
        schedule: args.schedule,
        failedJobsHistoryLimit: 3,
        successfulJobsHistoryLimit: 3,
        jobTemplate+: {
          spec+: {
            template+: {
              spec+: {
                restartPolicy: 'Never',
                containers_+: {
                  silence: kube.Container('job') {
                    image: image,
                    command: [ '/usr/local/bin/script.sh' ],
                    volumeMounts_+: {
                      scripts: {
                        mountPath: '/usr/local/bin/script.sh',
                        subPath: 'script.sh',
                        readOnly: true,
                      },
                    },
                  },
                },
                volumes_+: {
                  scripts: {
                    secret: {
                      secretName: scriptSecret.metadata.name,
                      defaultMode: std.parseOctal('0550'),
                    },
                  },
                },
              },
            },
          },
        },
      },
    } + com.makeMergeable(std.get(args, 'config', {})),
  ];

local cronjobs = std.flattenArrays([
  makeCronjob(name, params.cronjobs[name])
  for name in std.objectFields(params.cronjobs)
  if params.cronjobs[name] != null
]);

{
  cronjobs: cronjobs,
}
