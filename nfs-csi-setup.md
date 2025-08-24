# NFS CSI Driver Installation and Setup

This document explains how to install the NFS CSI driver on a Kubernetes cluster using Helm and configure it with a default StorageClass and VolumeSnapshotClass.

## Prerequisites

- A running Kubernetes cluster (K3s, kubeadm, etc.)
- `helm` installed
- `kubectl` installed
- NFS server available (can be local or remote)

---

## 1. Install NFS CSI Driver with Helm

Add the NFS CSI driver Helm repo and install it into the `kube-system` namespace:

```bash
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# Install the driver with snapshot support enabled
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs   --namespace kube-system   --set externalSnapshotter.enabled=true
```

---

## 2. Configure StorageClass and SnapshotClass

Wait a bit for pods to start:

```bash
sleep 30
```

Then apply the NFS StorageClass and VolumeSnapshotClass:

```bash
cat <<EOF | kubectl apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: nfsserver
  share: /data
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nfsvers=3
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-nfs-snapclass
driver: nfs.csi.k8s.io
deletionPolicy: Delete
EOF
```

This creates:

- A default StorageClass (`nfs-csi`) pointing to `nfsserver:/data`
- A VolumeSnapshotClass (`csi-nfs-snapclass`) for backups and restores

---

## 3. Verification

Check if everything is running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs
kubectl get sc
kubectl get volumesnapshotclass
```

Expected:

- NFS CSI pods are in `Running` state
- `nfs-csi` is the default StorageClass
- `csi-nfs-snapclass` is available for snapshots
