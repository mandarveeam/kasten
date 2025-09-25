# Single Node K3s Cluster with NFS CSI Driver Setup

This document explains how to set up a single-node K3s cluster and install the NFS CSI driver for persistent storage.

## Prerequisites

- A Linux VM or bare-metal server (tested on Alpine)
- User with `sudo` privileges
- `helm` installed
- ```bash
  wget https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz
  tar -xzvf helm-v3.19.0-linux-amd64.tar.gz
  sudo install linux-amd64/helm /usr/bin
  ```
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
  share: /share
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

- A default StorageClass (`nfs-csi`) pointing to `localhost:/share`
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
        - mountPath: "/share"
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
echo "hello world" > /share/hello.txt
cat /share/hello.txt
```

---

## Conclusion

You now have:

- A single-node K3s cluster
- NFS CSI driver installed
- Default StorageClass and SnapshotClass
- A working test PVC and Pod
---

## Optional Install NFS Locally
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

--- 
## Optional Before setting up make sure the IP is static IP 

```bash

#!/bin/bash
set -e

# The network interface to configure
API_IF="enp2s0"

# Get current IP/mask/gateway
echo "Detecting network configuration for interface: $API_IF..."
API_IP=$(ip -4 addr show dev $API_IF | awk '/inet / {print $2}' | cut -d/ -f1)
API_MASK=$(ip -4 addr show dev $API_IF | awk '/inet / {print $2}' | cut -d/ -f2)
API_GW=$(ip route | awk '/default/ && $5=="'$API_IF'" {print $3}' | sort -u | head -n1)

# Check if required variables are found
if [[ -z "$API_IP" || -z "$API_MASK" || -z "$API_GW" ]]; then
    echo "Error: Could not detect IP, Mask, or Gateway. Please check the network interface '$API_IF' and your connectivity."
    exit 1
fi

echo "Detected:"
echo " Interface : $API_IF"
echo " IP        : $API_IP"
echo " Mask      : $API_MASK"
echo " Gateway   : $API_GW"

# Backup old netplan config
echo "Backing up existing Netplan configuration..."
sudo mkdir -p /etc/netplan/backup
if [ -f /etc/netplan/50-cloud-init.yaml ]; then
  sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/backup/50-cloud-init.yaml.$(date +%s)
  echo "Backup created at /etc/netplan/backup/"
fi

# Write new netplan config
echo "Writing new Netplan configuration to /etc/netplan/50-cloud-init.yaml..."
cat <<EOF | sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
    $API_IF:
      addresses:
        - ${API_IP}/${API_MASK}
      routes:
        - to: default
          via: ${API_GW}
      nameservers:
        addresses: [${API_GW}, 8.8.8.8]
EOF

# Fix permissions
sudo chown root:root /etc/netplan/50-cloud-init.yaml
sudo chmod 600 /etc/netplan/50-cloud-init.yaml

# Apply config
echo "Generating and applying new configuration..."
sudo netplan generate
sudo netplan apply

echo "✅ Netplan updated successfully. $API_IF is now static at $API_IP"
```
---
