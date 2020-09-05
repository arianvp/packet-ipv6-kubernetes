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
