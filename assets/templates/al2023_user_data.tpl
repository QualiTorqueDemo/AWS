%{ if length(pre_bootstrap_user_data) > 0 ~}
${pre_bootstrap_user_data}
%{ endif ~}
%{ if enable_bootstrap_user_data ~}
---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${cluster_name}
    apiServerEndpoint: ${cluster_endpoint}
    certificateAuthority: ${cluster_auth_base64}
    cidr: ${cluster_service_cidr}
%{ if length(bootstrap_extra_args) > 0 ~}
  kubelet:
    config:
${indent(6, bootstrap_extra_args)}
%{ endif ~}
%{ endif ~}
%{ if length(post_bootstrap_user_data) > 0 ~}
${post_bootstrap_user_data}
%{ endif ~}
