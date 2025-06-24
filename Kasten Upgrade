# 📦 Kasten K10 v8.0.2 Upgrade Using Local Helm Chart and Private Registry

> ⚠️ Run all the below steps on a **jump host** that has access to both the **Internet** and your **private container registry**.

---

## 🔄 Step 1: Copy Images to Private Repository

Use the following one-liner to copy all Kasten images to your private container registry.  
Replace `repo.example.com` with your actual registry (including any required path).

```bash
docker run --rm -v $HOME/.docker:/home/kio/.docker \
  gcr.io/kasten-images/k10tools:8.0.2 \
  image copy --dst-registry repo.example.com
```

---

## 📥 Step 2: Download the K10 Helm Chart (v8.0.2)

Run the following command to download the chart as a `.tgz` archive:

```bash
helm repo update && helm fetch kasten/k10 --version=8.0.2
```

Ensure the file `k10-8.0.2.tgz` is downloaded in your current directory.

---

## ✏️ Step 3: Patch Missing Values

Create a new file named `values-patch.yaml` and add the following contents to it:

```yaml
vap:
  kastenPolicyPermissions:
    enabled: true
```

Save and close the file.

---

## 🚀 Step 4: Run the Helm Upgrade

Finally, perform the upgrade using the downloaded chart and patch file:

```bash
helm upgrade k10 ./k10-8.0.2.tgz \
  --namespace kasten-io \
  --reuse-values \
  -f values-patch.yaml
```
