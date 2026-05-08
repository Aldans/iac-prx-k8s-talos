# Talos cluster bootstrap.
#
# DNS naming pipeline:
#   - Proxmox VM name      : tls-cp-01            (see 01_vms.tf)
#   - Talos hostname       : tls-cp-01            (via machine.network.hostname)
#   - dnsmasq DNS record   : tls-cp-01.lab.lan    (auto-created by expand-hosts + domain)
#
# The very first machine-config apply uses the temporary DHCP IP from qemu-agent (DNS does not
# resolve yet — Talos has just learned its hostname). All Talos resources that take a `node`
# argument carry lifecycle.ignore_changes=[node] so DHCP renewals (the IP may change, the
# hostname won't) don't cause resource churn on subsequent applies.

locals {
  kubernetes_api_port = 6443

  # Prefixes that are NOT a node's DHCP-assigned IP and must be filtered out.
  # After Cilium is installed, qemu-agent reports many addresses (DHCP, pod IPs, Hubble,
  # overlay, etc.). We use the first two octets of pod_cidr (assumes a /16 — the common case).
  _pod_cidr_octets = split(".", split("/", var.pod_cidr)[0])
  pod_cidr_prefix  = "${local._pod_cidr_octets[0]}.${local._pod_cidr_octets[1]}."

  # First "real" (DHCP) IPv4 of every node.
  # Filter: not loopback, not link-local, not inside the Cilium pod CIDR.
  cp_initial_ips = {
    for name, vm in proxmox_virtual_environment_vm.talos_cp :
    name => one([
      for addr in flatten(vm.ipv4_addresses) :
      addr if !startswith(addr, "127.")
      && !startswith(addr, "169.254.")
      && !startswith(addr, local.pod_cidr_prefix)
      && length(split(".", addr)) == 4
    ])
  }

  worker_initial_ips = {
    for name, vm in proxmox_virtual_environment_vm.talos_worker :
    name => one([
      for addr in flatten(vm.ipv4_addresses) :
      addr if !startswith(addr, "127.")
      && !startswith(addr, "169.254.")
      && !startswith(addr, local.pod_cidr_prefix)
      && length(split(".", addr)) == 4
    ])
  }

  first_cp_name       = local.cp_node_names[0]
  first_cp_initial_ip = local.cp_initial_ips[local.first_cp_name]
  first_cp_fqdn       = "${local.first_cp_name}.${var.dns_domain}"

  # API-server endpoint baked into kubeconfig (kubectl) and used by talosctl.
  # FQDN of the first CP is stable across DHCP renewals but tied to a single node.
  # For full HA, swap to a Talos VIP (see CLAUDE.md, "Known limitations").
  cluster_endpoint = "https://${local.first_cp_fqdn}:${local.kubernetes_api_port}"

  # Shared part of machineconfig for both CP and worker — extracted to avoid duplication.
  # Per-node hostname and machine_type are injected per-node below.
  common_machine_config_patch = {
    cluster = {
      # CNI is disabled — Cilium is installed via Helm in 03_cilium.tf.
      network = {
        cni = {
          name = "none"
        }
      }
      # kube-proxy is disabled — Cilium provides kube-proxy replacement.
      proxy = {
        disabled = true
      }
    }
  }

  # talos_machine_configuration_apply only supports create/update/delete (no read).
  talos_apply_timeouts = {
    create = "5m"
    update = "5m"
    delete = "5m"
  }

  # SANs for the node-cert (Talos apid TLS) and for the kube-apiserver cert.
  # Without this, talosctl --talosconfig=... fails with x509 when connecting via FQDN —
  # Talos auto-adds only the short hostname (= machine.network.hostname), node IPs and
  # localhost to the SAN list, but NOT <hostname>.<dns_domain>.
  # When var.dns_domain changes, this list re-computes and Talos re-issues the certs.
  talos_cert_sans = concat(
    local.cp_fqdns,
    local.worker_fqdns,
    values(local.cp_initial_ips),
    values(local.worker_initial_ips),
  )

  # Optional registry mirror config patch (empty when var.registry_mirror is null).
  # Talos containerd uses the mirror first for the listed upstream hostnames,
  # then falls back to the upstream registry on a miss.
  registry_mirror_host = var.registry_mirror == null ? "" : regex("^https?://([^/]+)", var.registry_mirror.endpoint)[0]

  registry_mirror_patch = var.registry_mirror == null ? null : {
    machine = {
      registries = {
        mirrors = {
          "ghcr.io"         = { endpoints = [var.registry_mirror.endpoint] }
          "docker.io"       = { endpoints = [var.registry_mirror.endpoint] }
          "registry.k8s.io" = { endpoints = [var.registry_mirror.endpoint] }
          "quay.io"         = { endpoints = [var.registry_mirror.endpoint] }
        }
        config = {
          (local.registry_mirror_host) = {
            tls = merge(
              { insecureSkipVerify = var.registry_mirror.insecure_skip_verify },
              var.registry_mirror.ca_cert == null ? {} : { ca = var.registry_mirror.ca_cert },
            )
          }
        }
      }
    }
  }

  # The Talos provider 0.7.x emits hosts.toml with `capabilities = ['pull', 'resolve']`,
  # which makes the mirror authoritative for manifest resolution: a 404 from the mirror
  # (e.g. an image that has not been pulled-through yet) terminates the pull instead of
  # falling back to the upstream registry. We work around this by overwriting the
  # generated hosts.toml files via `machine.files`, dropping `resolve` from capabilities
  # and adding the `server = ...` upstream fallback line. The result: containerd resolves
  # manifests at the upstream and fetches blobs from the mirror — exactly what we want
  # for a pull-through cache like Zot.
  registry_upstream_servers = {
    "ghcr.io"         = "https://ghcr.io"
    "docker.io"       = "https://registry-1.docker.io"
    "registry.k8s.io" = "https://registry.k8s.io"
    "quay.io"         = "https://quay.io"
  }

  registry_hosts_files = var.registry_mirror == null ? [] : [
    for upstream, server_url in local.registry_upstream_servers : {
      path        = "/etc/cri/conf.d/hosts/${upstream}/hosts.toml"
      op          = "overwrite"
      permissions = 384 # 0o600
      content     = <<-TOML
        server = "${server_url}"

        [host."${var.registry_mirror.endpoint}"]
          capabilities = ["pull"]
          skip_verify = ${var.registry_mirror.insecure_skip_verify}
      TOML
    }
  ]

  registry_files_patch = length(local.registry_hosts_files) == 0 ? null : {
    machine = {
      files = local.registry_hosts_files
    }
  }
}

resource "talos_machine_secrets" "this" {}

# Talos client config (talosconfig) — used by talosctl from outside the cluster.
# endpoints lists ALL CPs by FQDN so talosctl can transparently fail over between them.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.cp_fqdns
}

# Control-plane machine config — shared template, hostname injected per-node.
# kubernetes_version is passed straight to the provider, which picks the right image tags.
data "talos_machine_configuration" "cp" {
  for_each = toset(local.cp_node_names)

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version

  config_patches = concat(
    [
      yamlencode({
        machine = {
          network = {
            hostname = each.key
          }
          certSANs = local.talos_cert_sans
        }
      }),
      yamlencode(local.common_machine_config_patch),
    ],
    local.registry_mirror_patch == null ? [] : [yamlencode(local.registry_mirror_patch)],
    local.registry_files_patch == null ? [] : [yamlencode(local.registry_files_patch)],
  )
}

data "talos_machine_configuration" "worker" {
  for_each = toset(local.worker_node_names)

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version

  config_patches = concat(
    [
      yamlencode({
        machine = {
          network = {
            hostname = each.key
          }
          certSANs = local.talos_cert_sans
        }
      }),
      yamlencode(local.common_machine_config_patch),
    ],
    local.registry_mirror_patch == null ? [] : [yamlencode(local.registry_mirror_patch)],
    local.registry_files_patch == null ? [] : [yamlencode(local.registry_files_patch)],
  )
}

# Apply machine config via the temporary DHCP IP (provided by qemu-agent through bpg/proxmox).
# After this apply Talos re-requests DHCP carrying its proper hostname → dnsmasq registers DNS.
# ignore_changes=[node] keeps DHCP renewals from churning this resource on every apply.
resource "talos_machine_configuration_apply" "cp" {
  for_each = toset(local.cp_node_names)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp[each.key].machine_configuration
  node                        = local.cp_initial_ips[each.key]

  timeouts = local.talos_apply_timeouts

  lifecycle {
    ignore_changes = [node]
  }
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = toset(local.worker_node_names)

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = local.worker_initial_ips[each.key]

  timeouts = local.talos_apply_timeouts

  lifecycle {
    ignore_changes = [node]
  }
}

# etcd bootstrap on the first CP. Runs exactly once per cluster lifetime.
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.cp]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.first_cp_initial_ip

  lifecycle {
    ignore_changes = [node]
  }
}

# Pull kubeconfig. The clusterEndpoint inside it equals the first-CP FQDN (see cluster_endpoint).
# replace_triggered_by — when cluster_endpoint changes (e.g. var.dns_domain is updated)
# Terraform recreates this resource so the new server URL lands in kubeconfig automatically;
# otherwise ./kubeconfig would keep the stale FQDN and kubectl would break silently.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.first_cp_initial_ip

  lifecycle {
    ignore_changes = [node]
    # When cluster_endpoint changes (e.g. var.dns_domain) → the machine config is re-applied →
    # this resource is recreated, and kubeconfig is re-issued with the new server URL.
    replace_triggered_by = [
      talos_machine_configuration_apply.cp,
    ]
  }
}

# Local files for kubectl and talosctl.
resource "local_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

resource "local_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/talosconfig"
  file_permission = "0600"
}

# Final cluster-health check — runs AFTER Cilium (see 03_cilium.tf), because nodes will never
# become Ready without a CNI, so this would deadlock if scheduled before Cilium.
#
# IMPORTANT: provider siderolabs/talos 0.7.1 parses control_plane_nodes/worker_nodes/endpoints
# of this data source through netip.ParseAddr — IPs only, NOT FQDNs (unlike
# talos_client_configuration where FQDN works). Hence we pass IPs here.
data "talos_cluster_health" "this" {
  depends_on = [
    helm_release.cilium,
    talos_machine_configuration_apply.cp,
    talos_machine_configuration_apply.worker,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = values(local.cp_initial_ips)
  control_plane_nodes  = values(local.cp_initial_ips)
  worker_nodes         = values(local.worker_initial_ips)

  timeouts = {
    read = "10m"
  }
}
