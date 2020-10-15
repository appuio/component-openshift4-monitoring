local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-monitoring', params.namespace);

{
  'openshift4-monitoring': app,
}
