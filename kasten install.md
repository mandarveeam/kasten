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
