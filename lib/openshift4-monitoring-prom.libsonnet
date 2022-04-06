/**
 * \file prom.libsonnet
 * \brief Helpers to create Prometheus Operator CRs.
 *        API reference: https://github.com/prometheus-operator/prometheus-operator/blob/master/Documentation/api.md
 */

local kube = import 'lib/kube.libjsonnet';

// Define Prometheus Operator API versions
local api_version = {
  monitoring: 'monitoring.coreos.com/v1',
};

{
  api_version: api_version,

  /**
  * \brief Helper to create PrometheusRule objects.
  *
  * \arg The name of the PrometheusRule.
  * \return A PrometheusRule object.
  */
  PrometheusRule(name):
    kube._Object(api_version.monitoring, 'PrometheusRule', name),

  /**
  * \brief Helper to create Prometheus objects.
  *
  * \arg The name of the Prometheus.
  * \return A Prometheus object.
  */
  Prometheus(name):
    kube._Object(api_version.monitoring, 'Prometheus', name),

  /**
  * \brief Helper to create ServiceMonitor objects.
  *
  * \arg The name of the ServiceMonitor.
  * \return A ServiceMonitor object.
  */
  ServiceMonitor(name):
    kube._Object(api_version.monitoring, 'ServiceMonitor', name),

  /**
  * \brief Helper to create Alertmanager objects.
  *
  * \arg The name of the Alertmanager.
  * \return A Alertmanager object.
  */
  Alertmanager(name):
    kube._Object(api_version.monitoring, 'Alertmanager', name),
}
