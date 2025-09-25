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
---

## Kasten K10 Service Account Setup

### 1. Create the Service Account

```bash
kubectl create serviceaccount my-k10-sa -n kasten-io
```
### 2. Bind ClusterRoles

Bind the service account with `k10-admin`, `kasten-admin`, and `cluster-admin` roles.

```bash
kubectl create clusterrolebinding my-k10-sa-k10-admin   --clusterrole=k10-admin   --serviceaccount=kasten-io:my-k10-sa

kubectl create clusterrolebinding my-k10-sa-kasten-admin   --clusterrole=kasten-admin   --serviceaccount=kasten-io:my-k10-sa

kubectl create clusterrolebinding my-k10-sa-cluster-admin   --clusterrole=cluster-admin   --serviceaccount=kasten-io:my-k10-sa
```
### 3. Create a Permanent Token

Generate a Secret of type `kubernetes.io/service-account-token` associated with the ServiceAccount.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: my-k10-sa-token
  namespace: kasten-io
  annotations:
    kubernetes.io/service-account.name: "my-k10-sa"
type: kubernetes.io/service-account-token
EOF
```
### 4. Display the Token

Run the following command to retrieve and decode the token:

```bash
kubectl get secret my-k10-sa-token -n kasten-io -o jsonpath="{.data.token}" | base64 --decode
```

This token can then be used to log in to the K10 dashboard or API.

---
