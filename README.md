# IPV6 cluster on Packet

Sets up IPV6-native cluster using packet.

This shows how a modern container fabric should look like. Without any NAT or
overlay nonsense; but a pure IP/Layer-3 networking fabric.

Instead of using an overlay network, each pod is directly assigned an IPV6
address. Routes to pods are announced directly to the packet router BGP.

Furthermore ClusterIPs are also allocated from a public range.  This allows for
some cool tricks. For example, this means we can announce the apiserver
ClusterIP to be publically reachable, giving us a load-balancer ingress to our
APIServer for free. We can then use this to set up a multi-master cluster
without any external loadbalancers.

The IPV6-native world is a bit different than you're used to. Normally in k8s
we kind of rely on NAT and overlaynetworks for a false sense of security, and
hence most people don't even set up NetworkPolicy's for their services and pods
properly. However, with IPV6 there are no overlays and NAT; so we are forced to
take security seriously and explicitly define NetworkPolicies to make sure only
the things that _should_ talk to eachother _can_ talk to eachother.

# Usage

Create an `.envrc.local` with your secrets:
```
export TF_VAR_kubeadm_certificate_key=
export TF_VAR_kubeadm_token=
export PACKET_AUTH_TOKEN=
export DIGITALOCEAN_TOKEN=
```

```
$ direnv allow
$ apply
```

`apply` might fail to get the `kubeconfig` on first try; as the cluster might still be bootstrapping.
Type `apply` again to get it.  The script is idempotent.  It is important to make run it until it succeeds
as this also configures the `BGPPeer`s with the packet routers.


# Stream notes

## Packet, pods, ipv6

![packet](https://docs.projectcalico.org/images/anatomy-of-a-packet.svg)


* Pod network is flat. all pods should reach eachother without NAT
* pod cidr != node cidr != service cidr
* Overlay networks (usually; but not neccessarily; E.g. GCP sets up routes directly for pods)
* Pod network usually a private range.
![vxlan](https://docs.projectcalico.org/images/anatomy-of-an-overlay-packet.svg)
* What if each pod just got a public ip address? => No need for overlays
* Very possible with IPv6   (Packet gives you a /56)
* Packet allows us to announce routes using BGP.
* Calico can announce pod ip addresses to BGP automatically
*  https://docs.projectcalico.org/reference/architecture/design/l3-interconnect-fabric
* _downward default_ network
![downward](https://docs.projectcalico.org/images/l3-fabric-downward-default.png)


## Advertising ClusterIPs
* We can directly advertise kubernetes services using BGP too!
* Will use ECMP routing to loadbalance between nodes. So highly available LB
* Just make sure that the ip range is also a public ipv6 range
* No need for external load-balancer; or metallb, or whatever! All services are
  reachable through public IP Address

## externalTrafficPolicy: Local vs Cluster
* Show what it means for routes

## bbbbut What about security?! (Out of scope probably due to time constraints!)

* Overlay networks and NAT give a false sense of security. This is what IPv6 advocates yell all day
* Instead, we want fine-grained routing policies that tell which pods and reach what services, and what services are publically reachable
* We can define Kubernetes NetworkPolicies for this! https://kubernetes.io/docs/concepts/services-networking/network-policies/
* _Zero Trust networks_ https://docs.projectcalico.org/security/adopt-zero-trust
* Service Mesh like Istio

## Whats next - Security


