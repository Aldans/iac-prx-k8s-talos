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
- **Optional Ingress controller** (`var.ingress_enabled = true`) — Cilium serves `kind: Ingress` directly via embedded Envoy. Replaces ingress-nginx without changing manifest API. The created LoadBalancer service picks up its IP from a `CiliumLoadBalancerIPPool` (managed in the GitOps repo, not in this module).

## Usage

```hcl
module "cilium" {
  source = "../../../modules/cilium"

  cluster_name    = var.cluster_name
  cilium_version  = var.cilium_version
  pod_cidr        = var.pod_cidr
  cilium_devices  = var.cilium_devices

  ingress_enabled = true       # Cilium becomes the default IngressClass

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
| <a name="input_gateway_api_create_class"></a> [gateway\_api\_create\_class](#input\_gateway\_api\_create\_class) | Whether the chart creates the `cilium` GatewayClass automatically. Set false if multiple Cilium installations share a cluster (rare). Ignored when gateway\_api\_enabled = false. | `bool` | `true` | no |
| <a name="input_gateway_api_enabled"></a> [gateway\_api\_enabled](#input\_gateway\_api\_enabled) | Enable Cilium's native Gateway API support. Requires Gateway API CRDs to be installed in the cluster (out of scope for this module — managed in the GitOps repo). | `bool` | `false` | no |
| <a name="input_gateway_api_secrets_namespace"></a> [gateway\_api\_secrets\_namespace](#input\_gateway\_api\_secrets\_namespace) | Namespace where Cilium will look up TLS secrets referenced by Gateway listeners. Empty (default) means same-namespace as the Gateway. Ignored when gateway\_api\_enabled = false. | `string` | `""` | no |
| <a name="input_ingress_default"></a> [ingress\_default](#input\_ingress\_default) | Register the Cilium IngressClass as the cluster default. When true, `kind: Ingress` resources without an explicit ingressClassName route to Cilium. Ignored when ingress\_enabled = false. | `bool` | `true` | no |
| <a name="input_ingress_enabled"></a> [ingress\_enabled](#input\_ingress\_enabled) | Enable Cilium's built-in Ingress controller. Replaces ingress-nginx for the same `kind: Ingress` API. Requires kubeProxyReplacement (already on). | `bool` | `false` | no |
| <a name="input_ingress_loadbalancer_mode"></a> [ingress\_loadbalancer\_mode](#input\_ingress\_loadbalancer\_mode) | How Cilium provisions LB services for Ingress. `shared` = one LB service for ALL Ingresses (recommended for home labs — fewer external IPs). `dedicated` = per-Ingress LB. Ignored when ingress\_enabled = false. | `string` | `"shared"` | no |
| <a name="input_k8s_client_burst"></a> [k8s\_client\_burst](#input\_k8s\_client\_burst) | K8s API client burst capacity for cilium-agent. See k8s\_client\_qps. | `number` | `20` | no |
| <a name="input_k8s_client_qps"></a> [k8s\_client\_qps](#input\_k8s\_client\_qps) | K8s API client QPS for cilium-agent. Bumped from default 5 → 10 when L2 announcements are on, since lease polling generates additional requests. Set higher (50+) for clusters with many announced IPs. | `number` | `10` | no |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | Address Cilium uses to reach the API server. Default `localhost` exploits Talos KubePrism so Cilium does not depend on a single CP being alive. | `string` | `"localhost"` | no |
| <a name="input_k8s_service_port"></a> [k8s\_service\_port](#input\_k8s\_service\_port) | Port Cilium uses to reach the API server. Default 7445 = Talos KubePrism. | `number` | `7445` | no |
| <a name="input_kubeconfig_path"></a> [kubeconfig\_path](#input\_kubeconfig\_path) | Filesystem path of a kubeconfig that grants access to the target cluster. Consumed both by the wait\_apiserver provisioner and by the helm provider configured in the parent. | `string` | n/a | yes |
| <a name="input_kubeconfig_sha"></a> [kubeconfig\_sha](#input\_kubeconfig\_sha) | SHA-256 of the kubeconfig contents — used as the trigger for the wait\_apiserver provisioner. When the kubeconfig is regenerated (e.g. cluster\_endpoint changes) the wait re-runs. | `string` | n/a | yes |
| <a name="input_l2_announcements_enabled"></a> [l2\_announcements\_enabled](#input\_l2\_announcements\_enabled) | Enable Cilium L2 announcements feature. Required when using CiliumLoadBalancerIPPool + CiliumL2AnnouncementPolicy to make LB IPs reachable on the LAN. | `bool` | `false` | no |
| <a name="input_l2_announcements_lease_duration"></a> [l2\_announcements\_lease\_duration](#input\_l2\_announcements\_lease\_duration) | How long a node holds the L2 lease for an announced IP before it expires. Format: Go duration string. Default 15s strikes a balance between failover speed and API server load. | `string` | `"15s"` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | CIDR for Cilium pod networks (ipv4NativeRoutingCIDR). | `string` | n/a | yes |
| <a name="input_wait_attempts"></a> [wait\_attempts](#input\_wait\_attempts) | How many 5-second polling iterations wait\_apiserver does before giving up (default = 60 → 5 minutes). | `number` | `60` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_helm_release_id"></a> [helm\_release\_id](#output\_helm\_release\_id) | ID of the Cilium Helm release. Useful as a depends\_on hook for resources that must run only after Cilium is ready (e.g. talos\_cluster\_health, flux\_bootstrap\_git). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Kubernetes namespace Cilium is installed into. |
| <a name="output_version"></a> [version](#output\_version) | Cilium chart version actually applied. |
<!-- END_TF_DOCS -->
