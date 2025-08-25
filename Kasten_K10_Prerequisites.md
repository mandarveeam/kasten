# Kasten K10 Installation Prerequisites

This document outlines the prerequisites required before installing **Kasten K10** in your Kubernetes environment.

---

## Prerequisites

Before proceeding with the installation, ensure the following requirements are met:

1. **Helm**  
   - Helm must be installed on the system from which you are deploying Kasten K10.  
   - [Helm Installation Guide](https://helm.sh/docs/intro/install/)

2. **kubectl**  
   - The `kubectl` CLI must be installed and configured to communicate with your Kubernetes cluster.  
   - [kubectl Installation Guide](https://kubernetes.io/docs/tasks/tools/)

3. **Access to the Internet**  
   - Required for pulling Kasten K10 images directly from public container registries.  
   - If your environment does not have internet access, see the **Air-Gapped Installation** section below.

4. **Backup Storage Backend**  
   At least one of the following storage backends must be available for storing backups:
   - S3-compatible object storage  
   - NFS (Network File System)  
   - SMB (Server Message Block)

5. **Cluster Permissions**  
   - You must have **cluster-admin** rights in the Kubernetes cluster where Kasten K10 will be deployed.  
   - This is required for installing CRDs and configuring cluster-wide resources.

6. **Jump Host for UI Access**  
   - A jump host or bastion with access to the Kubernetes cluster should be available.  
   - This will allow you to securely connect to and access the Kasten K10 UI.

---

## Air-Gapped Environments

If your Kubernetes cluster does **not** have internet access:

1. Download the **k10tools** binary from an internet-connected environment.  
   [K10Tools Documentation](https://docs.kasten.io/latest/install/airgap.html)

2. Use `k10tools` to push required Kasten K10 images into your private container registry.

3. Configure Helm to pull images from the private registry during installation.

---

## Next Steps

Once prerequisites are satisfied, proceed with the Kasten K10 installation using Helm. Refer to the official documentation:  
[https://docs.kasten.io/latest/install/](https://docs.kasten.io/latest/install/)
