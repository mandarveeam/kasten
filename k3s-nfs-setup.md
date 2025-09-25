# Single Node K3s Cluster with NFS CSI Driver Setup

This document explains how to set up a single-node K3s cluster and install the NFS CSI driver for persistent storage.

## Prerequisites

- A Linux VM or bare-metal server (tested on Alpine)
- User with `sudo` privileges
- `helm` installed
- `kubectl` installed
- NFS server available (can be local or remote)

---

## 1. Install K3s (Single Node Cluster)

Run the following script to install **K3s v1.32.0+k3s1** with your node IP configured correctly:

```bash
API_IP=$(ip -4 addr show | awk '/inet 192\.168\.1\./ {print $2}' | cut -d/ -f1 | head -n1)

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.0+k3s1" sh -s - server   --node-ip "${API_IP}"   --advertise-address "${API_IP}"   --tls-san "${API_IP}"   --write-kubeconfig-mode 644
```

This installs K3s and sets up your kubeconfig.

---

## 2. Install NFS CSI Driver with Helm

Add the NFS CSI driver Helm repo and install it into the `kube-system` namespace:

```bash
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# Copy K3s kubeconfig to default location for kubectl & helm
sudo cp /etc/rancher/k3s/k3s.yaml .kube/config && sudo chown $(whoami):$(whoami) .kube/config

# Install the driver with snapshot support enabled
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs   --namespace kube-system   --set externalSnapshotter.enabled=true
```

---

## 3. Configure StorageClass and SnapshotClass

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
  server: localhost
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

- A default StorageClass (`nfs-csi`) pointing to `localhost:/data`
- A VolumeSnapshotClass (`csi-nfs-snapclass`) for backups and restores

---

## 4. Verification

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

---

## 5. Test PVC and Pod

You can test if NFS-backed storage is working by deploying a PVC and a Pod.

```bash
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: nfs-csi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: app
      image: busybox
      command: [ "sleep", "3600" ]
      volumeMounts:
        - mountPath: "/data"
          name: test-volume
  volumes:
    - name: test-volume
      persistentVolumeClaim:
        claimName: test-pvc
EOF
```

Check the pod:

```bash
kubectl get pod test-pod
```

Once the pod is running, you can exec into it and verify storage:

```bash
kubectl exec -it test-pod -- sh
# inside pod
echo "hello world" > /data/hello.txt
cat /data/hello.txt
```

---

## Conclusion

You now have:

- A single-node K3s cluster
- NFS CSI driver installed
- Default StorageClass and SnapshotClass
- A working test PVC and Pod
---

# Optional Install NFS Locally
use following script to install and configure NFS server. 

```bash

#!/bin/bash
set -e

# Create the shared folder
sudo mkdir -p /share
sudo chown nobody:nogroup /share
sudo chmod 777 /share

# Update packages and install NFS server
sudo apt update -y
sudo apt install -y nfs-kernel-server

# Add /share to exports if not already present
if ! grep -q "^/share" /etc/exports; then
    echo "/share *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
fi

# Apply export changes
sudo exportfs -ra

# Enable and start NFS services
sudo systemctl enable nfs-kernel-server
sudo systemctl start nfs-kernel-server

echo "NFS share /share created and exported successfully."
```
