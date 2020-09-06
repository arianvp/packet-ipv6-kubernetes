%{ for network in master.network ~}
%{ if network.family == 6 ~}
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: ${master.hostname}
spec:
  peerIP: ${network.gateway}
  asNumber: 65530
  node: ${master.hostname}
apiVersion:
%{ endif ~}
%{ endfor ~}
%{ for device in workers ~}
%{ for network in device.network ~}
%{ if network.family == 6 ~}
---
apiVersion: projectcalico.org/v3
kind: BGPPeer
metadata:
  name: ${device.hostname}
spec:
  peerIP: ${network.gateway}
  asNumber: 65530
  node: ${device.hostname}
%{ endif ~}
%{ endfor ~}
%{ endfor ~}