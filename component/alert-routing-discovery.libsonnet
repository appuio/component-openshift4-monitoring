local kube = import 'kube-ssa-compat.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local ard = import 'syn/alert-routing-discovery.libsonnet';

local inv = com.inventory();
local params = inv.parameters;

local nullReceiver = '__component_openshift4_monitoring_null';

local adParams = params.openshift4_monitoring.alertManagerAutoDiscovery;
local amConfig = params.openshift4_monitoring.alertManagerConfig;


local alertmanagerConfig = ard.alertmanagerConfig(
  adParams,
  amConfig,
  nullReceiver,
  params.openshift4_monitoring.fallback_team,
);

{
  debugConfigMap: kube.ConfigMap('discovery-debug') {
    data: ard.debugConfigMapData(
      adParams,
      amConfig,
      nullReceiver,
      params.openshift4_monitoring.fallback_team,
    ),
  },
  alertmanagerConfig: alertmanagerConfig,
}
