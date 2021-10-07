
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

  # control_plane_endpoint = # "${local.subdomain}.${local.basedomain}"
  # TODO: kube-vip?
  control_plane_endpoint = metal_device.controlplane.access_public_ipv6

  metal_asn = 65530 # NOTE: this wasn't actually documented anywhere? I found it "somewhere"

  K8S_VERSION  = "v1.22.2"
  KUBEADM_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubeadm"

  KUBELET_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubelet"

  KUBECTL_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubectl"

  CALICOCTL_URL  = "https://github.com/projectcalico/calicoctl/releases/download/v3.16.0/calicoctl"

  # TODO: Change to HTTPS once ISRG X1 is used. Sent a request for that to flatcar folks. Other option is to reverse proxy flatcar
  # re: https://community.letsencrypt.org/t/production-chain-changes/150739/1
  # re: https://github.com/ipxe/ipxe/pull/116 re:
  # https://github.com/ipxe/ipxe/pull/112 re:
  # https://lists.ipxe.org/pipermail/ipxe-devel/2020-May/007042.html
  IPXE_URL = "http://beta.release.flatcar-linux.net/amd64-usr/current/flatcar_production_packet.ipxe"


  ignition_base = templatefile("./ignition/base.yaml", {
    KUBEADM_URL    = local.KUBEADM_URL
    KUBELET_URL    = local.KUBELET_URL
    KUBECTL_URL    = local.KUBECTL_URL
    CALICOCTL_URL  = local.CALICOCTL_URL
    metal_asn     = local.metal_asn
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
      token               = var.kubeadm_token
    })
  ]
}

resource "metal_bgp_session" "controlplane" {
  device_id      = metal_device.controlplane.id
  address_family = "ipv6"
}

resource "metal_device" "worker" {
  count            = 2
  hostname         = "worker${count.index}"
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
      control_plane_endpoint = local.control_plane_endpoint
      certificate_key        = null
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
  value = templatefile("manifests/bgppeer.yaml.tpl", {
    workers             = metal_device.worker
    controlplane              = metal_device.controlplane
    metal_asn          = local.metal_asn
    service_cidr_range  = local.service_cidr_range
    external_cidr_range = local.external_cidr_range
  })
}
