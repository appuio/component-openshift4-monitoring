#!/bin/bash
set -euo pipefail

curl_opts=( https://alertmanager-main.openshift-monitoring.svc.cluster.local:9095/api/v2/silences --cacert /etc/ssl/certs/serving-certs/service-ca.crt --header 'Content-Type: application/json' --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" --resolve "alertmanager-main.openshift-monitoring.svc.cluster.local:9095:$(getent hosts alertmanager-operated.openshift-monitoring.svc.cluster.local | awk '{print $1}' | head -n 1)" --silent )

comment='Silence non syn alerts'

read -rd '' body << EOF
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
  "createdBy": "Kubernetes object \`cronjob/silence\` in the monitoring namespace",
  "comment": "${comment}"
}
EOF

id=$(curl "${curl_opts[@]}" | jq -r ".[] | select(.status.state == \"active\") | select(.comment == \"${comment}\") | .id" | head -n 1)

if [ -n "${id}" ]; then
  body=$(echo "${body}{\"id\":\"${id}\"}" | jq -s '.[0] * .[1]')
fi

curl "${curl_opts[@]}" -XPOST -d "${body}"
