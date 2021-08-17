
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

  K8S_VERSION  = "v1.19.0"
  KUBEADM_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubeadm"
  KUBEADM_HASH = "f1f993f3a5a440c18474d30a5b89ac01c6ce13600d93be1f234b86289a138dab1e20496de3d4882d92b54625a2efd24b56e6b0fb40ab0b660553c06c616f08ab"

  KUBELET_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubelet"
  KUBELET_HASH = "dd5cc49c2f867a73658e3196f147df2336d50118ff2a09690a58ea9f5f8ed57e6bee2e43407dc10afc362a8da7932fee08f380d0c787137750fe2293064cc601"

  KUBECTL_URL  = "https://storage.googleapis.com/kubernetes-release/release/${local.K8S_VERSION}/bin/linux/amd64/kubectl"
  KUBECTL_HASH = "e27b8d65b49296be4366b828ef179416e50f22029d6a927e5b111ff001f553ce4603426121c1502575ee19613ff14203989b5cd42998684b66a053ae32e570ee"

  CALICOCTL_URL  = "https://github.com/projectcalico/calicoctl/releases/download/v3.16.0/calicoctl"
  CALICOCTL_HASH = "c011c4b81c29e17e570850c6a4a07062a5dd7ddccfbe902994dd5bff712f3148b8e028c1c788dc738d0ed73524f635cb516a781fc22522838c8651d904dd847f"


  ignition_base = templatefile("./ignition/base.yaml", {
    KUBEADM_URL    = local.KUBEADM_URL
    KUBEADM_HASH   = local.KUBEADM_HASH
    KUBELET_URL    = local.KUBELET_URL
    KUBELET_HASH   = local.KUBELET_HASH
    KUBECTL_URL    = local.KUBECTL_URL
    KUBECTL_HASH   = local.KUBECTL_HASH
    CALICOCTL_URL  = local.CALICOCTL_URL
    CALICOCTL_HASH = local.CALICOCTL_HASH
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
  operating_system = "flatcar_alpha"
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
  count            = local.worker_count
  hostname         = "worker${count.index}"
  plan             = "t1.small.x86"
  facilities       = ["ams1"]
  operating_system = "flatcar_alpha"
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
