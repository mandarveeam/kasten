# Add Kasten Helm repo

```bash
helm repo add kasten https://charts.kasten.io/
helm repo update
```
# Create namespace
```bash
kubectl create namespace kasten-io
```

# Install K10 with token authentication and persistence set to nfs-csi
```bash

helm install k10 kasten/k10 \
  --namespace kasten-io \
  --set auth.tokenAuth.enabled=true \
  --set global.persistence.storageClass=nfs-csi
```
---
# Make sure Storage class is annotated
Replace your storageclass name and volumesnapshotclass name 

```bash
kubectl annotate storageclass nfs-csi k10.kasten.io/volume-snapshot-class=csi-nfs-snapclass
```
---
# NFS PV and PVC for Location Profile
To Use NFS as location profile create 2 yamls files and apply them. 
pv.yaml Replace your nfs version, Path, Server name. 

```bash
apiVersion: v1
kind: PersistentVolume
metadata:
   name: localnfspv
spec:
   capacity:
      storage: 10Gi
   volumeMode: Filesystem
   accessModes:
      - ReadWriteMany
   persistentVolumeReclaimPolicy: Retain
   storageClassName: nfs-csi 
   mountOptions:
      - hard
      - nfsvers=3
   nfs:
      path: /share
      server: localhost
```

pvc.yaml 
```bash
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
   name: k10nfs
   namespace: kasten-io
spec:
   storageClassName: nfs-csi 
   accessModes:
      - ReadWriteMany
   resources:
      requests:
         storage: 10Gi
```
