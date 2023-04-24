local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_monitoring;

local app_name = 'cortex-tenant-ns-label';
local namespace_name = 'syn-cortex-tenant-ns-label';

local namespace_meta = {
  metadata+: {
    namespace: namespace_name,
  },
};

local namespace = kube.Namespace(namespace_name);

local secret = kube.Secret(app_name) + namespace_meta {
  stringData: {
    CONFIG: params.cortex_tenant_ns_label.config,
  },
};


local deployment = kube.Deployment('cortex-tenant-ns-label') + namespace_meta {
  spec+: {
    template+: {
      metadata+: {
        labels+: {
          app: 'cortex-tenant-ns-label',
        },
      },
      spec+: {
        containers_:: {
          [app_name]: kube.Container(app_name) {
            image: 'ghcr.io/vshn/cortex-tenant-ns-label:latest',
            resources: {
              limits: {
                cpu: params.cortex_tenant_ns_label.limits.cpu,
                memory: params.cortex_tenant_ns_label.limits.memory,
              },
              requests: {
                cpu: params.cortex_tenant_ns_label.requests.cpu,
                memory: params.cortex_tenant_ns_label.requests.memory,
              },
            },
            ports_:: {
              http: { containerPort: 8080 },
            },
            livenessProbe: {
              httpGet: {
                path: '/alive',
                port: 8080,
              },
              initialDelaySeconds: 30,
              periodSeconds: 30,
            },
            envFrom: [
              {
                secretRef: {
                  name: secret.metadata.name,
                },
              },
            ],
          },
        },
        serviceAccountName+: app_name,
      },
    },
  },
};

local service = kube.Service('cortex-tenant-ns-label') + namespace_meta {
  target_pod:: deployment.spec.template,
  target_container_name:: app_name,
};

local service_account = kube.ServiceAccount(app_name) + namespace_meta {
};

local cluster_role = kube.ClusterRole(app_name + ':namespace-reader') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'namespaces' ], verbs: [ 'get', 'list' ] },
  ],
};

local cluster_role_binding = kube.ClusterRoleBinding(app_name + '-namespace-reader') {
  subjects_: [ service_account ],
  roleRef_: cluster_role,
};

local network_policies_cluster_metrics = [
  kube.NetworkPolicy('allow-from-openshift-monitoring') + namespace_meta {
    spec: {
      ingress: [ {
        from: [
          { podSelector: { matchLabels: { prometheus: 'k8s' } } },
          { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'openshift-monitoring' } } },
        ],
        ports: [ { port: 8080, protocol: 'TCP' } ],
      } ],
      podSelector: {
        matchLabels: {
          name: 'cortex-tenant-ns-label',
        },
      },
      policyTypes: [ 'Ingress' ],
    },
  },
];

local network_policies_user_metrics = [
  if params.enableUserWorkload then
    kube.NetworkPolicy('allow-from-openshift-user-workload-monitoring') + namespace_meta {
      spec: {
        ingress: [ {
          from: [
            { podSelector: { matchLabels: { prometheus: 'k8s' } } },
            { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'openshift-user-workload-monitoring' } } },
          ],
          ports: [ { port: 8080, protocol: 'TCP' } ],
        } ],
        podSelector: {
          matchLabels: {
            name: 'cortex-tenant-ns-label',
          },
        },
        policyTypes: [ 'Ingress' ],
      },
    },
];

[
  cluster_role,
  namespace,
  service_account,
  cluster_role_binding,
  deployment,
  service,
  secret,
] + network_policies_cluster_metrics + network_policies_user_metrics
