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
    silence: |||
      #!/bin/bash

      curl_opts=( https://alertmanager-main.openshift-monitoring.svc.cluster.local:9095/api/v2/silences --cacert /etc/ssl/certs/serving-certs/service-ca.crt --header 'Content-Type: application/json' --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" --resolve alertmanager-main.openshift-monitoring.svc.cluster.local:9095:$(getent hosts alertmanager-operated.openshift-monitoring.svc.cluster.local | awk '{print $1}' | head -n 1) --silent )

      comment='Silence non syn alerts'

      read -d '' body << EOF
      {
        "matchers": [
          {
            "name": "syn",
            "value": "",
            "isRegex": false
          },
          {
            "name": "alertname",
            "value": ".+",
            "isRegex": true
          }
        ],
        "startsAt": "$(date -u +'%Y-%m-%dT%H:%M:%S')",
        "endsAt": "$(date -u +'%Y-%m-%dT%H:%M:%S' --date '+1 year')",
        "createdBy": "cronjob/silence",
        "comment": "${comment}"
      }
      EOF

      id=$(curl "${curl_opts[@]}" | jq -r ".[] | select(.status.state == \"active\") | select(.comment == \"${comment}\") | .id" | head -n 1)

      if [ -n "${id}" ]; then
        body=$(echo "${body}{\"id\":\"${id}\"}" | jq -s '.[0] * .[1]')
      fi

      curl "${curl_opts[@]}" -XPOST -d "${body}"
    |||,
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
