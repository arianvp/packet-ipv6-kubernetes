
variable "kubeadm_token" {
  type        = string
  description = "The token use for bootstrapping the kubernetes cluster.\nGenerate with: \n$ kubeadm token generate"
}

variable "kubeadm_certificate_key" {
  type        = string
  description = "The key used to encrypt the control-plane certificates.\nGenerate with: \n$ kubeadm alpha certs certificate-key\n"
}

locals {
  worker_count        = 2
  pod_cidr_range      = cidrsubnet(data.metal_precreated_ip_block.addresses.cidr_notation, 8, 1)
  service_cidr_range_ = cidrsubnet(data.metal_precreated_ip_block.addresses.cidr_notation, 8, 2)
  # NOTE: subnet size for services in kubernetes can only be 20 bits in size;
  # hence allocate a smaller block in the larger /64 block
  service_cidr_range  = cidrsubnet(local.service_cidr_range_, 44, 0)
  external_cidr_range = cidrsubnet(data.metal_precreated_ip_block.addresses.cidr_notation, 8, 3)

  # NOTE: If we run kube-proxy and calico-node on the control-plane, we can use this as the control_plane_endpoint!!!
  kubernetes_service = cidrhost(local.service_cidr_range, 1)

  metal_asn = 65530 # NOTE: this wasn't actually documented anywhere? I found it "somewhere"

  K8S_VERSION = "v1.22.3"
  KUBEADM_URL = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubeadm"

  KUBELET_URL = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubelet"

  KUBECTL_URL = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubectl"

  CALICOCTL_URL = "https://github.com/projectcalico/calicoctl/releases/download/v3.20.2/calicoctl"

  # TODO: Change to HTTPS once ISRG X1 is used. Sent a request for that to flatcar folks. Other option is to reverse proxy flatcar
  # re: https://community.letsencrypt.org/t/production-chain-changes/150739/1
  # re: https://github.com/ipxe/ipxe/pull/116 re:
  # https://github.com/ipxe/ipxe/pull/112 re:
  # https://lists.ipxe.org/pipermail/ipxe-devel/2020-May/007042.html
  IPXE_URL = "https://raw.githubusercontent.com/arianvp/packet-ipv6-kubernetes/metal/ignition/bootstrap.ipxe"


  ignition_base = templatefile("./ignition/base.yaml", {
    KUBEADM_URL   = local.KUBEADM_URL
    KUBELET_URL   = local.KUBELET_URL
    KUBECTL_URL   = local.KUBECTL_URL
    CALICOCTL_URL = local.CALICOCTL_URL
  })

}

# This is a pre-existing project, where I create and delete a device, such that
# the
data "metal_project" "kubernetes" {
  name = "kubernetes"
}

# This only works if the project we refer to had a device created at some point
# so create and delete a dummy device in the UI before this data source actually works
data "metal_precreated_ip_block" "addresses" {
  facility       = "ams1"
  project_id     = data.metal_project.kubernetes.id
  address_family = 6
  public         = true
}

resource "metal_device" "controlplane" {
  hostname         = "controlplane"
  plan             = "t1.small.x86"
  facilities       = ["ams1"]
  operating_system = "custom_ipxe"
  ipxe_script_url  = local.IPXE_URL
  billing_cycle    = "hourly"
  project_id       = data.metal_project.kubernetes.id
  user_data        = data.ct_config.controlplane.rendered

}

data "ct_config" "controlplane" {
  content = local.ignition_base
  snippets = [
    templatefile("./ignition/controlplane.yaml", {
      # TODO: There is a cycle. instead use coreos-metadata?
      # node_ip = metal_device.controlplane.access_public_ipv6
      pod_cidr_range      = local.pod_cidr_range
      service_cidr_range  = local.service_cidr_range
      external_cidr_range = local.external_cidr_range
      certificate_key     = var.kubeadm_certificate_key
      metal_asn           = local.metal_asn
      token               = var.kubeadm_token
    })
  ]
}

resource "metal_bgp_session" "controlplane" {
  device_id      = metal_device.controlplane.id
  address_family = "ipv6"
}

resource "random_pet" "worker" {
  count     = local.worker_count
  prefix    = "worker"
  separator = "-"
  keepers = {
    # NOTE: Done because user_data might contain sensitive data
    user_data = sha256(data.ct_config.worker.rendered)
  }
}

resource "metal_device" "worker" {
  count            = local.worker_count
  hostname         = random_pet.worker[count.index].id
  plan             = "t1.small.x86"
  facilities       = ["ams1"]
  operating_system = "custom_ipxe"
  ipxe_script_url  = local.IPXE_URL
  billing_cycle    = "hourly"
  project_id       = data.metal_project.kubernetes.id
  user_data        = data.ct_config.worker.rendered
}

data "ct_config" "worker" {
  content = local.ignition_base
  snippets = [
    templatefile("./ignition/worker.yaml", {
      token                  = var.kubeadm_token
      control_plane_endpoint = "[${local.kubernetes_service}]:443"
      certificate_key        =  var.kubeadm_certificate_key
    })
  ]
}

resource "metal_bgp_session" "worker" {
  count          = local.worker_count
  device_id      = metal_device.worker[count.index].id
  address_family = "ipv6"
}

output "controlplane_ipv4" {
  value = metal_device.controlplane.access_public_ipv4
}

output "controlplane_ipv6" {
  value = metal_device.controlplane.access_public_ipv6
}

output "calico_bgp_peers" {
  description = "A calico manifest describing the topology of the cluster. You should apply this to thhe cluster to set up all the needed routes."
  sensitive   = true
  value = templatefile("manifests/bgppeer.yaml.tpl", {
    workers             = metal_device.worker
    controlplane        = metal_device.controlplane
    metal_asn           = local.metal_asn
    service_cidr_range  = local.service_cidr_range
    external_cidr_range = local.external_cidr_range
  })
}

resource "null_resource" "write_kubeconfig" {
  provisioner "local-exec" {
    command = <<EOF
      curl --insecure --connect-timeout 500 'https://[${local.kubernetes_service}]/api/v1/namespaces/kube-public/configmaps/cluster-info' | jq -r .data.kubeconfig > oidc.conf
      kubectl config set-credentials oidc \
        --kubeconfig=oidc.conf \
        --exec-api-version=client.authentication.k8s.io/v1beta1 \
        --exec-command=kubectl \
        --exec-arg=oidc-login \
        --exec-arg=get-token \
        --exec-arg=--oidc-issuer-url=https://oidc.arianvp.me \
        --exec-arg=--oidc-client-id=ASF4Os1wJysH6uWvJV9PvyNiph4y4O84tGCHj1FZEE8
    EOF
  }
}

