# Offline Installation Guide – NFS CSI Driver (Helm)

> **Important:** Do **NOT** use `--version latest`. Pull the chart without specifying `--version`, or specify an exact version string if you know it.

---

## Overview
This document describes how to prepare the **Helm chart** and **container images** required to install the `csi-driver-nfs` chart in an **air‑gapped / offline** Kubernetes environment.

You will:
1. Download the Helm chart and `values.yaml` on an online machine.  
2. Extract the image repository + tag entries from `values.yaml`.  
3. Pull the required images, save them to a tarball, and transfer to the offline network.  
4. Load images onto nodes or into a private registry.  
5. Update `values.yaml` to point to your private registry and install the chart offline.

---

## Prerequisites (online machine)
- `helm` (v3+) installed  
- `docker` or `podman` (or `ctr`/`crane`) for pulling and saving images  
- `kubectl` (for validation after install) available in offline cluster  
- Access to transfer method (scp, USB drive, portable registry sync)  
- Optional tools: `yq` (recommended), `awk`, `sed`, `grep`

---

## 1) Download the Helm chart (online machine)

```bash
# Add the repo and update (if you prefer using the official repo entry)
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

# Pull the chart locally (do NOT use --version latest)
# This will create a directory named csi-driver-nfs/
helm pull csi-driver-nfs/csi-driver-nfs --untar
```

If you prefer to download directly from the GitHub charts folder, you can `git clone` the repo or manually fetch the chart files from GitHub.

---

## 2) Find the image repositories and tags
Open the downloaded `values.yaml` (inside `csi-driver-nfs/values.yaml`) and extract image repository + tag pairs.

You told me to use this `grep` for repositories — run:

```bash
cd csi-driver-nfs
grep -R "repository" values.yaml
```

Example output (your `values.yaml` likely contains lines like these):
```
repository: registry.k8s.io/sig-storage/nfsplugin
repository: registry.k8s.io/sig-storage/csi-provisioner
repository: registry.k8s.io/sig-storage/csi-resizer
repository: registry.k8s.io/sig-storage/csi-snapshotter
repository: registry.k8s.io/sig-storage/livenessprobe
repository: registry.k8s.io/sig-storage/csi-node-driver-registrar
repository: registry.k8s.io/sig-storage/snapshot-controller
```

To pair each `repository` with its `tag`, use one of these methods:

**(A) Using `awk` (simple, works for common layouts):**
```bash
awk 'BEGIN{repo=""} /repository:/ {repo=$2} /tag:/ {if (repo!="") print repo ":" $2}' values.yaml
```

**(B) Using `yq` (recommended if installed — more robust):**
```bash
# prints repository:tag pairs for entries that have both
yq eval '. as $root | .. | select(type == "map" and has("repository")) | .repository + ":" + ( .tag // "latest" )' values.yaml
```

Save the list (one per line) to a file for pulling:
```bash
awk 'BEGIN{repo=""} /repository:/ {repo=$2} /tag:/ {if (repo!="") print repo ":" $2}' values.yaml > images-to-pull.txt
```

**Important:** Inspect `images-to-pull.txt` and verify tags — do not assume `latest`. If a tag is missing for an image in `values.yaml`, determine the proper tag (check chart `README` or chart `Chart.lock` or GitHub release) before pulling.

---

## 3) Pull and save images (online machine)
With `images-to-pull.txt` prepared and verified, pull images and save to a tarball.

Example (use `docker` or `podman`):

```bash
# pull all images listed (example using a while loop)
while read -r img; do
  echo "Pulling $img"
  docker pull "$img"
done < images-to-pull.txt

# Save all pulled images to a single tar (edit list as needed)
docker save -o nfs-csi-images.tar $(awk '{print $1}' images-to-pull.txt)
```

If any images are hosted on `mcr.microsoft.com` or other registries, include them too if referenced in your `values.yaml`.

---

## 4) Transfer images and chart to the offline environment
Copy these files to the offline environment by your chosen method:

- `csi-driver-nfs/` directory (the chart)
- `images-to-pull.txt`
- `nfs-csi-images.tar`

Example:
```bash
scp nfs-csi-images.tar user@offline-host:/tmp/
scp -r csi-driver-nfs/ user@offline-host:/tmp/
```

---

## 5) Load images on the offline side (either to nodes or to private registry)

### Option A — Load directly on each node (Docker runtime)
```bash
# on target node
docker load -i /tmp/nfs-csi-images.tar
```

### Option B — Push to private registry (preferred for clusters)
1. Load images (or re-tag then push from a machine that can reach your private registry):

```bash
docker load -i nfs-csi-images.tar

# Tag + push each image to your registry, example:
docker tag registry.k8s.io/sig-storage/nfsplugin:Vx.y.z my-registry.local/csi/nfsplugin:Vx.y.z
docker push my-registry.local/csi/nfsplugin:Vx.y.z
```

2. Repeat tagging+push for every image in `images-to-pull.txt`.

---

## 6) Update `values.yaml` to point to your private registry
Open `csi-driver-nfs/values.yaml` and replace each `repository:` entry to use your private registry.

Example `sed` replacements (adjust `my-registry.local` and image paths to your naming convention):

```bash
# Example replacements - run from inside the chart directory
sed -i 's|registry.k8s.io/sig-storage/nfsplugin|my-registry.local/csi/nfsplugin|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/csi-provisioner|my-registry.local/sig-storage/csi-provisioner|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/csi-resizer|my-registry.local/sig-storage/csi-resizer|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/csi-snapshotter|my-registry.local/sig-storage/csi-snapshotter|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/livenessprobe|my-registry.local/sig-storage/livenessprobe|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/csi-node-driver-registrar|my-registry.local/sig-storage/csi-node-driver-registrar|g' values.yaml
sed -i 's|registry.k8s.io/sig-storage/snapshot-controller|my-registry.local/sig-storage/snapshot-controller|g' values.yaml
```

If you pushed images with different paths or tags, adjust accordingly (also replace tags if you used different tags).

If your private registry requires authentication, configure `imagePullSecrets` in the `values.yaml` or create a Kubernetes `Secret` in the `kube-system` namespace and reference it.

---

## 7) Install the chart from local directory (offline cluster)
On a machine that can reach your offline cluster and has `helm`:

```bash
# Ensure namespace exists
kubectl create namespace kube-system --dry-run=client -o yaml | kubectl apply -f -

# Install from local chart directory
helm install csi-driver-nfs ./csi-driver-nfs \
  --namespace kube-system \
  --set externalSnapshotter.enabled=true
```

If you already have a previous release, use `helm upgrade --install`:

```bash
helm upgrade --install csi-driver-nfs ./csi-driver-nfs \
  --namespace kube-system \
  --set externalSnapshotter.enabled=true
```

---

## 8) Verify installation
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs
kubectl describe daemonset -n kube-system csi-driver-nfs
kubectl logs -n kube-system <pod-name>  # for troubleshooting
```

Check for image pull errors:
```bash
kubectl get events -n kube-system --field-selector type=Warning
kubectl describe pod <pod-name> -n kube-system
```

---

## 9) Troubleshooting tips
- If pods show `ErrImagePull` / `ImagePullBackOff`:
  - Confirm the exact image name:tag exists in your private registry.
  - Confirm nodes can reach the private registry and credentials (if required).
  - Confirm `values.yaml` has the correct repository and tag.

- If `externalSnapshotter.enabled=true` fails, try enabling related components in `values.yaml` (some charts provide separate flags for `snapshot-controller`).

- Re-run `helm upgrade --install` after fixing images or values.

---

## Appendix — Quick command summary

```bash
# 1) Download chart
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update
helm pull csi-driver-nfs/csi-driver-nfs --untar

# 2) Extract repo:tag pairs (example)
awk 'BEGIN{repo=""} /repository:/ {repo=$2} /tag:/ {if (repo!="") print repo ":" $2}' csi-driver-nfs/values.yaml > images-to-pull.txt

# 3) Pull + save
while read -r img; do docker pull "$img"; done < images-to-pull.txt
docker save -o nfs-csi-images.tar $(awk '{print $1}' images-to-pull.txt)

# 4) Transfer and load on offline side
docker load -i nfs-csi-images.tar

# 5) Replace repo in values.yaml to private registry and install
sed -i 's|registry.k8s.io/sig-storage|my-registry.local/sig-storage|g' csi-driver-nfs/values.yaml
helm install csi-driver-nfs ./csi-driver-nfs --namespace kube-system --set externalSnapshotter.enabled=true
```

---

If you'd like, I can:
- Replace the placeholder `my-registry.local` with your actual private registry host and produce a final `values.yaml` diff; or
- Try to extract the exact **tags** from the `values.yaml` you have (if you upload it here) and produce a ready-to-pull `images-to-pull.txt` and `docker pull` script.

