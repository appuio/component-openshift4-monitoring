local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local syn_teams = import 'syn/syn-teams.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local renderer = import 'espejote-templates/rules-renderer-v1.libsonnet';

/* --- Secret PrometheusRule Testing ---------------------------------------- */

local secretRulesTestsConfig = {
  ignoreGroups: [ 'DropThisGroup' ],
  ignoreNames: [],
  ignoreWarnings: [ 'TestDropSeverityWarning' ],
  ignoreUserWorkload: [ 'TestUserWorkloadNamespace', 'TestUserWorkloadAlertmanager', 'TestUserWorkloadPrometheus' ],
  patchRules: {
    TestPatchRule: {
      'for': '30m',
      labels: {
        additional: 'test',
        severity: 'critical',
      },
    },
  },
  teamLabel: syn_teams.teamForApplication(inv.parameters._instance),
  includeNamespaces: params.alerts.includeNamespaces,
  excludeNamespaces: params.alerts.excludeNamespaces,
};

local secretRulesTests = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    labels+: {
      'espejote.io/ignore': 'openshift4-monitoring-rules',
    },
    name: 'syn-prometheus-rules-testing',
    namespace: params.namespace,
  },
  spec: {
    groups: [
      {
        name: 'Special',
        rules: [
          {
            alert: 'Watchdog',
            expr: |||
              vector(1)
            |||,
          },
        ],
      },
      {
        name: 'DropThisGroup',
        rules: [
          {
            alert: 'AlertmanagerFailedReload',
            expr: |||
              # Without max_over_time, failed scrapes could create false negatives, see
              # https://www.robustperception.io/alerting-on-gauges-in-prometheus-2-0 for details.
              max_over_time(alertmanager_config_last_reload_successful{job=~"alertmanager-main|alertmanager-user-workload"}[5m]) == 0
            |||,
          },
          {
            alert: 'AlertmanagerMembersInconsistent',
            expr: |||
              # Without max_over_time, failed scrapes could create false negatives, see
              # https://www.robustperception.io/alerting-on-gauges-in-prometheus-2-0 for details.
              max_over_time(alertmanager_cluster_members{job=~"alertmanager-main|alertmanager-user-workload"}[5m])
              < on (namespace,service) group_left
              count by (namespace,service) (max_over_time(alertmanager_cluster_members{job=~"alertmanager-main|alertmanager-user-workload"}[5m]))
            |||,
          },
        ],
      },
      {
        name: 'DontDropThisGroup',
        rules: [
          {
            alert: 'TestNamespaceReplacement',
            expr: |||
              max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff", namespace=~"(openshift-.*|kube-.*|default)",job="kube-state-metrics"}[5m]) >= 1
            |||,
            'for': '15m',
          },
          {
            alert: 'TestDropSeverityInfo',
            expr: |||
              max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff", namespace=~"(openshift-.*|kube-.*|default)",job="kube-state-metrics"}[5m]) >= 1
            |||,
            'for': '15m',
            labels: {
              severity: 'info',
            },
          },
          {
            alert: 'TestDropSeverityWarning',
            expr: |||
              max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) >= 1
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestDontDropSeverityWarning',
            expr: |||
              max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) >= 1
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestDontIgnoreUserWorkload',
            expr: |||
              min by (cluster,controller,namespace) (max_over_time(prometheus_operator_ready{job="prometheus-operator", namespace=~"openshift-monitoring|openshift-user-workload-monitoring"}[5m]) == 0)
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestUserWorkloadNamespace',
            expr: |||
              min by (cluster,controller,namespace) (max_over_time(prometheus_operator_ready{job="prometheus-operator", namespace=~"openshift-monitoring|openshift-user-workload-monitoring"}[5m]) == 0)
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestUserWorkloadAlertmanager',
            expr: |||
              max_over_time(alertmanager_config_last_reload_successful{job=~"alertmanager-main|alertmanager-user-workload"}[5m]) == 0
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestUserWorkloadPrometheus',
            expr: |||
              max_over_time(prometheus_remote_storage_shards_max{job=~"prometheus-k8s|prometheus-user-workload"}[5m])
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
          {
            alert: 'TestPatchRule',
            expr: |||
              max_over_time(prometheus_remote_storage_shards_max{job=~"prometheus-k8s|prometheus-user-workload"}[5m])
            |||,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
          },
        ],
      },
    ],
  },
};

/* --- Additional Rules ----------------------------------------------------- */

local additionalRules = prom.generateRules('syn-additional-rules', params.rules) {
  metadata: {
    name: 'syn-additional-rules',
    namespace: params.namespace,
    labels+: {
      'espejote.io/ignore': 'openshift4-monitoring-rules',
    },
  },
};

{
  [if std.length(params.rules) > 0 then '50_rules_additional']: additionalRules,
  [if std.get(params, '_enableSecretRuleTests', false) then '99_rules_secret_tests']: renderer.process(secretRulesTests, secretRulesTestsConfig, {}, false),
}
