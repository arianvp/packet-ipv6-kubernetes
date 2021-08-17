---
apiVersion: projectcalico.org/v3
kind: BGPConfiguration
metadata:
  name: default
spec:
  logSeverityScreen: Info
  nodeToNodeMeshEnabled: false
  asNumber: 65000
  # This will cause all cluster ip's to be announced to metal's routers.
  # Allowing us to reach kubernetes services from the outside! pretty dope
  serviceExternalIPs:
    - cidr: "${external_cidr_range}"


%{ for network in master.network ~}
%{ if network.family == 6 ~}
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: "${master.hostname}"
spec:
  peerIP: "${network.gateway}"
  asNumber: ${metal_asn}
  node: "${master.hostname}"
%{ endif ~}
%{ endfor ~}

%{ for device in workers ~}
%{ for network in device.network ~}
%{ if network.family == 6 ~}
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: "${device.hostname}"
spec:
  peerIP: "${network.gateway}"
  asNumber: ${metal_asn}
  node: "${device.hostname}"
%{ endif ~}
%{ endfor ~}
%{ endfor ~}
