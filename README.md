### Terraform Proxmox Talos Cilium

Iac terraform for the create of k8s with dynamically quantity of nodes with cilium on proxmox and talos.

For vms network on proxmox used dhcp and dns (dnsmasq) installed on proxmox node.

Examle config dnsmasq:

```
user@pv:$ cat /etc/dnsmasq.conf

domain-needed
bogus-priv
no-resolv
server=1.1.1.1
interface=vmbr1
expand-hosts
domain=my.domain
dhcp-range=10.0.0.20,10.0.0.240,255.255.255.0,72h
dhcp-option=option:router,10.0.0.1
dhcp-option=3,10.0.0.2
dhcp-authoritative
listen-address=127.0.0.1,10.0.0.2
address=/mf.my-domain/10.0.0.2
address=/ing.mf.my-domain/10.0.0.245  # for ngins-ingress-controller
```

For start - clone repo add your changes and run:

```sh
terraform init --upgrade && terraform validate && terraform plan && terraform apply --auto-approve
```

For get talosconfig and kubeconfig file use next commands:
```
terraform output -raw talosconfig > ~/.talos/config
terraform output -raw kubeconfig > ~/.kube/config
```

As result have k8s cluster with cilium

```sh
➜ k get no -o wide
NAME        STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE         KERNEL-VERSION   CONTAINER-RUNTIME
tls-cp-01   Ready    control-plane   29m   v1.32.0   10.0.0.117    <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1
tls-cp-02   Ready    control-plane   29m   v1.32.0   10.0.0.49     <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1
tls-cp-03   Ready    control-plane   29m   v1.32.0   10.0.0.37     <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1
tls-wr-01   Ready    <none>          29m   v1.32.0   10.0.0.128    <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1
tls-wr-02   Ready    <none>          29m   v1.32.0   10.0.0.138    <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1
tls-wr-03   Ready    <none>          29m   v1.32.0   10.0.0.35     <none>        Talos (v1.9.1)   6.12.6-talos     containerd://2.0.1

```

**References**

Main article: 
- https://olav.ninja/talos-cluster-on-proxmox-with-terraform

Additional links:
- https://github.com/winlinuxmatt/kubernetes_iac
- https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/#the-top
