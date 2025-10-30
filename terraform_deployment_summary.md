# Terraform Deployment Summary

## Overview
This Terraform configuration provisions a complete Azure environment for Kasten K10 on AKS (Azure Kubernetes Service). It sets up networking, compute, identity, and storage resources in a unified deployment.

---

## Resources Created

### 1. **Resource Group**
- **Name:** `${var.prefix}-rg`
- **Purpose:** Container for all Azure resources (AKS, storage account, identity, etc.)

---

### 2. **Azure Storage Account**
- **Name:** `${var.prefix}stgacct`
- **Purpose:** Used for Kasten backups and object storage (blob container)
- **Features:**
  - Replication: `LRS` (Locally Redundant Storage)
  - Account Tier: Standard

---

### 3. **Azure AD Application**
- **Name:** `${var.prefix}-kasten-app`
- **Purpose:** Represents the application identity for Kasten K10 to interact with Azure APIs.

---

### 4. **Azure AD Service Principal**
- **Name:** `${var.prefix}-kasten-sp`
- **Purpose:** Enables secure API access using the Kasten application credentials.

---

### 5. **Service Principal Password**
- **Purpose:** Authentication secret for the Service Principal.
- **Output Variables:**
  - `kasten_sp_client_id`
  - `kasten_sp_client_secret`

---

### 6. **Azure AKS Cluster**
- **Name:** `${var.prefix}-aks`
- **Purpose:** The Kubernetes cluster where Kasten K10 will be installed.
- **Configuration:**
  - Node count: 2
  - VM size: `Standard_B4ms`
  - Network plugin: Azure CNI
  - RBAC: Enabled
  - Managed Identity: Enabled

---

### 7. **Outputs**
After running `terraform apply`, the following outputs are displayed:

| Output Name               | Description |
|----------------------------|--------------|
| `resource_group_name`      | The name of the created resource group |
| `aks_cluster_name`         | The name of the AKS cluster |
| `storage_account_name`     | The name of the Azure Storage Account |
| `kasten_sp_client_id`      | Client ID for the Service Principal |
| `kasten_sp_client_secret`  | Secret value for the Service Principal |

---

## Usage Notes
- You can use the `client_id` and `client_secret` outputs to authenticate Kasten K10 with Azure.
- The storage account can be used as a backup target.
- The AKS cluster will serve as the deployment base for Kasten K10 Helm charts.

---

## Example Commands

```bash
terraform init
terraform plan
terraform apply
```

Once deployed, retrieve credentials using:

```bash
az aks get-credentials --resource-group <prefix>-rg --name <prefix>-aks
```
