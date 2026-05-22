# `modules/cloudflare-tunnel`

Bootstraps a Cloudflare Tunnel for the cluster:

1. Creates the Tunnel resource on Cloudflare (`config_src=local`).
2. Generates the shared `TunnelSecret` (32 random bytes, b64).
3. Resolves the public zone (`data.cloudflare_zone`) and exposes its ID +
   the tunnel CNAME target as outputs — downstream `cloudflare-public-app`
   module instances use these to register per-app DNS records.
4. Writes a Kubernetes `Secret` containing `credentials.json` for the
   cloudflared Deployment to mount.
5. Writes a Kubernetes `ConfigMap` carrying `TUNNEL_ID` so the Deployment can
   pass it on the command line (`cloudflared tunnel run $(TUNNEL_ID)`).

This module does NOT create any public DNS records itself — those are managed
per-app by `modules/cloudflare-public-app` so that each gets its own
hostname-scoped edge certificate (Free-tier Universal SSL does not cover
two-level wildcards like `*.apps.<zone>`).

The actual cloudflared workload (Deployment, config.yaml with routes) lives
in the Flux repo at `home-lab-flux/infrastructure/controllers/cloudflared/`.

## Why `config_src = "local"`

Two operating modes for a tunnel:

| Mode | Routes managed in | When to use |
|---|---|---|
| `cloudflare` (remote) | Zero Trust dashboard (UI / API) | Quick start; multi-team admin via CF UI |
| `local` | `config.yaml` mounted into cloudflared | **GitOps** — routes are code, change = `git push` |

We pick `local` to keep public-route changes inside the Flux repo (PR / review /
audit trail / `git revert` for rollback).

## Why decouple TUNNEL_ID from `config.yaml`

Locally-managed tunnels normally hardcode the tunnel UUID in `config.yaml`:

```yaml
tunnel: 3f1e...                    # ← couples this file to the TF-managed tunnel
credentials-file: /etc/cloudflared/creds/credentials.json
ingress:
  - hostname: hubble.apps.example.com
    service: http://cilium-gateway-lab.gateway.svc.cluster.local:80
  - service: http_status:404
```

Instead, the Deployment runs `cloudflared tunnel run $(TUNNEL_ID)` and
`config.yaml` omits the top-level `tunnel:` key. This way:

- `config.yaml` (routes) is pure GitOps — devs PR routes without ever
  touching `terraform apply`.
- `TUNNEL_ID` (lifecycle: changes only on tunnel rebuild) is TF-managed.
- The two layers are decoupled — the natural seam for this architecture.

## Usage

```hcl
module "cloudflare_tunnel" {
  source = "../../../modules/cloudflare-tunnel"

  account_id    = var.cloudflare_account_id
  public_domain = var.public_domain        # e.g. "example.com"
  tunnel_name   = "${var.cluster_name}-home-lab"

  # Flux creates the namespace via infrastructure/controllers/cloudflared/.
  # Keep create_namespace = false on second and later applies.
  create_namespace = false

  depends_on = [
    # Cluster + Flux must be up so the namespace exists.
    module.flux_bootstrap,
  ]
}
```

The parent stack supplies the `cloudflare` and `kubernetes` providers — this
module does not configure them itself.

## API token scopes

The CF token in `credentials.auto.tfvars` (`cloudflare_api_token`) needs:

- **Account** › **Cloudflare Tunnel** › **Edit**
- **Zone** › **DNS** › **Edit** (limited to the target zone is fine)
- **Zone** › **Zone** › **Read** (limited to the target zone)

Create at: Cloudflare dashboard → My Profile → API Tokens → Create Custom Token.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.36 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 2.36 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_zero_trust_tunnel_cloudflared.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_tunnel_cloudflared) | resource |
| [kubernetes_config_map.tunnel_id](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map) | resource |
| [kubernetes_namespace.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace) | resource |
| [kubernetes_secret.credentials](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret) | resource |
| [random_id.tunnel_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID. Find at: Cloudflare dashboard → right sidebar → 'Account ID'. | `string` | n/a | yes |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | When true, the module creates the namespace itself. Default is true so the Secret and ConfigMap can land before Flux first-reconciles the Deployment. Flux is configured not to manage the namespace (no namespace.yaml in infrastructure/controllers/cloudflared/), so there is no ownership conflict. | `bool` | `true` | no |
| <a name="input_credentials_secret_name"></a> [credentials\_secret\_name](#input\_credentials\_secret\_name) | Name of the Secret holding credentials.json — mounted by the cloudflared Deployment. | `string` | `"cloudflared-credentials"` | no |
| <a name="input_kubernetes_namespace"></a> [kubernetes\_namespace](#input\_kubernetes\_namespace) | Kubernetes namespace where the cloudflared credentials Secret and tunnel-id ConfigMap are written. Must match the namespace the cloudflared Deployment runs in (managed by Flux). | `string` | `"cloudflared"` | no |
| <a name="input_public_domain"></a> [public\_domain](#input\_public\_domain) | Public zone in Cloudflare under which the tunnel hostnames are created. The zone must already exist in the account. | `string` | n/a | yes |
| <a name="input_tunnel_id_configmap_name"></a> [tunnel\_id\_configmap\_name](#input\_tunnel\_id\_configmap\_name) | Name of the ConfigMap that exposes TUNNEL\_ID as an env var to the cloudflared Deployment. Decoupling the tunnel ID from the config.yaml lets routes stay in Flux as pure GitOps artefacts. | `string` | `"cloudflared-tunnel-id"` | no |
| <a name="input_tunnel_name"></a> [tunnel\_name](#input\_tunnel\_name) | Display name for the Cloudflare Tunnel resource. Shown in the Zero Trust dashboard. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_credentials_secret_name"></a> [credentials\_secret\_name](#output\_credentials\_secret\_name) | Name of the Kubernetes Secret that the cloudflared Deployment mounts at /etc/cloudflared/creds/credentials.json. |
| <a name="output_tunnel_cname_target"></a> [tunnel\_cname\_target](#output\_tunnel\_cname\_target) | Hostname any additional DNS record should point at if you want to route extra zones through the same tunnel. Format: <tunnel-id>.cfargotunnel.com. |
| <a name="output_tunnel_id"></a> [tunnel\_id](#output\_tunnel\_id) | UUID of the Cloudflare Tunnel resource. Same value that the cloudflared Deployment reads via the TUNNEL\_ID ConfigMap entry. |
| <a name="output_tunnel_id_configmap_name"></a> [tunnel\_id\_configmap\_name](#output\_tunnel\_id\_configmap\_name) | Name of the Kubernetes ConfigMap that exposes TUNNEL\_ID to the Deployment via envFrom. |
| <a name="output_tunnel_name"></a> [tunnel\_name](#output\_tunnel\_name) | Display name of the tunnel — useful for `cloudflared tunnel list` and the Zero Trust dashboard. |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | Cloudflare zone ID of the public domain — handy for downstream resources (Access apps, Page Rules, additional records). |
<!-- END_TF_DOCS -->
