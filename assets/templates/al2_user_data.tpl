#!/bin/bash
set -e
%{ if length(pre_bootstrap_user_data) > 0 ~}
${pre_bootstrap_user_data}
%{ endif ~}
%{ if enable_bootstrap_user_data ~}
B64_CLUSTER_CA=${cluster_auth_base64}
API_SERVER_URL=${cluster_endpoint}
/etc/eks/bootstrap.sh ${cluster_name} --kubelet-extra-args '${bootstrap_extra_args}' --b64-cluster-ca $B64_CLUSTER_CA --apiserver-endpoint $API_SERVER_URL
%{ endif ~}
%{ if length(post_bootstrap_user_data) > 0 ~}
${post_bootstrap_user_data}
%{ endif ~}
