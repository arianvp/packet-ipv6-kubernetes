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
  asNumber: 65530
  node: "${device.hostname}"
%{ endif ~}
%{ endfor ~}
%{ endfor ~}
%{ for device in additional_masters ~}
%{ for network in device.network ~}
%{ if network.family == 6 ~}
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: ${device.hostname}
spec:
  peerIP: "${network.gateway}"
  asNumber: 65530
  node: "${device.hostname}"
%{ endif ~}
%{ endfor ~}
%{ endfor ~}