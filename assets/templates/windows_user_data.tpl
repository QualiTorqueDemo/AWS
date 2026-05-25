<powershell>
%{ if length(pre_bootstrap_user_data) > 0 ~}
${pre_bootstrap_user_data}
%{ endif ~}
%{ if enable_bootstrap_user_data ~}
[string]$EKSBootstrapScriptFile = "$env:ProgramFiles\Amazon\EKS\Start-EKSBootstrap.ps1"
& $EKSBootstrapScriptFile -EKSClusterName "${cluster_name}" -APIServerEndpoint "${cluster_endpoint}" -Base64ClusterCA "${cluster_auth_base64}" -KubeletExtraArgs "${bootstrap_extra_args}" 3>&1 4>&1 5>&1 6>&1
%{ endif ~}
%{ if length(post_bootstrap_user_data) > 0 ~}
${post_bootstrap_user_data}
%{ endif ~}
</powershell>
