#!/bin/bash
set -euo pipefail

curl_opts=( https://alertmanager-main.openshift-monitoring.svc.cluster.local:9095/api/v2/silences --cacert /etc/ssl/certs/serving-certs/service-ca.crt --header 'Content-Type: application/json' --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" --resolve "alertmanager-main.openshift-monitoring.svc.cluster.local:9095:$(getent hosts alertmanager-operated.openshift-monitoring.svc.cluster.local | awk '{print $1}' | head -n 1)" --silent )

while IFS= read -r silence; do
  comment=$(printf %s "${silence}" | jq -r '.comment')

  body=$(printf %s "$silence" | \
    jq \
      --arg startsAt "$(date -u +'%Y-%m-%dT%H:%M:%S' --date '-1 min')" \
      --arg endsAt "$(date -u +'%Y-%m-%dT%H:%M:%S' --date '+1 year')" \
      --arg createdBy "Kubernetes object \`cronjob/silence\` in the monitoring namespace" \
      '.startsAt = $startsAt | .endsAt = $endsAt | .createdBy = $createdBy'
  )

  id=$(curl "${curl_opts[@]}" | jq -r ".[] | select(.status.state == \"active\") | select(.comment == \"${comment}\") | .id" | head -n 1)
  if [ -n "${id}" ]; then
    body=$(printf %s "${body}" | jq --arg id "${id}" '.id = $id')
  fi

  curl "${curl_opts[@]}" -XPOST -d "${body}"
done <<<"$(printf %s "${SILENCES_JSON}" | jq -cr '.[]')"
