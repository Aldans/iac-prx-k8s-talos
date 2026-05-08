# `modules/cilium`

Installs Cilium as the CNI + kube-proxy replacement on a freshly-bootstrapped cluster, with a robust readiness gate that prevents the "Cilium hangs" failure mode (Helm trying to talk to an API server that has not finished starting).

The module produces no infra of its own beyond a single Helm release; it is consumed once per cluster.

## Behaviour

```
input: kubeconfig_path + kubeconfig_sha (from talos-cluster module)
    ↓
null_resource.wait_apiserver       ← polls `kubectl get --raw=/readyz` up to 5 min
    ↓
helm_release.cilium                ← wait=true, atomic=true, timeout=600s
    ↓
output: helm_release_id            ← downstream resources (e.g. talos_cluster_health,
                                     flux_bootstrap_git) can use this for depends_on
```

The Helm values template (`templates/values.yaml.tftpl`) configures Cilium for **Talos** specifically:
- `kubeProxyReplacement: true` (Talos has no kube-proxy)
- `k8sServiceHost: localhost` + `k8sServicePort: 7445` — Talos KubePrism, an in-cluster TCP load balancer that fronts every CP API server, so Cilium does not depend on a single CP being alive.
- `routingMode: native` + `autoDirectNodeRoutes: true` + `ipv4NativeRoutingCIDR = var.pod_cidr`.
- Hubble + Hubble UI enabled.

## Usage

```hcl
module "cilium" {
  source = "../../../modules/cilium"

  cluster_name    = var.cluster_name
  cilium_version  = var.cilium_version
  pod_cidr        = var.pod_cidr
  cilium_devices  = var.cilium_devices

  kubeconfig_path = module.talos_cluster.kubeconfig_path
  kubeconfig_sha  = module.talos_cluster.kubeconfig_sha

  depends_on = [module.talos_cluster]
}
```

The parent must declare a `helm` provider configured with the same `kubeconfig_path` — modules cannot configure providers themselves.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.1.1 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [null_resource.wait_apiserver](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cilium_devices"></a> [cilium\_devices](#input\_cilium\_devices) | Network interfaces Cilium uses for native routing. Glob patterns supported (eth+, ens+). | `string` | `"eth0"` | no |
| <a name="input_cilium_version"></a> [cilium\_version](#input\_cilium\_version) | Cilium Helm chart version. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cilium cluster name (passed into helm values as cluster.name). | `string` | n/a | yes |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | Address Cilium uses to reach the API server. Default `localhost` exploits Talos KubePrism so Cilium does not depend on a single CP being alive. | `string` | `"localhost"` | no |
| <a name="input_k8s_service_port"></a> [k8s\_service\_port](#input\_k8s\_service\_port) | Port Cilium uses to reach the API server. Default 7445 = Talos KubePrism. | `number` | `7445` | no |
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Filesystem path of a kubeconfig that grants access to the target cluster. Consumed both by the wait\_apiserver provisioner and by the helm provider configured in the parent. | `string` | n/a | yes |
| <a name="input_kubeconfig_sha"></a> [kubeconfig\_sha](#input\_kubeconfig\_sha) | SHA-256 of the kubeconfig contents — used as the trigger for the wait\_apiserver provisioner. When the kubeconfig is regenerated (e.g. cluster\_endpoint changes) the wait re-runs. | `string` | n/a | yes |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | CIDR for Cilium pod networks (ipv4NativeRoutingCIDR). | `string` | n/a | yes |
| <a name="input_wait_attempts"></a> [wait\_attempts](#input\_wait\_attempts) | How many 5-second polling iterations wait\_apiserver does before giving up (default = 60 → 5 minutes). | `number` | `60` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_id"></a> [helm\_release\_id](#output\_helm\_release\_id) | ID of the Cilium Helm release. Useful as a depends\_on hook for resources that must run only after Cilium is ready (e.g. talos\_cluster\_health, flux\_bootstrap\_git). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace Cilium is installed into. |
| <a name="output_version"></a> [version](#output\_version) | Cilium chart version actually applied. |
<!-- END_TF_DOCS -->
