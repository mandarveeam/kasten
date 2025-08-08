# Kasten VBR Admin Access Setup

This manifest creates a service account named `vbr-admin` in the `kasten-io` namespace and binds it to the `k10-admin` and `kasten-admin` ClusterRoles, granting it full access to the Kasten K10 APIs. Additionally, a long-lived token is generated for API access (e.g., for use by Veeam Backup & Replication).

## Resources Created

### 1. ServiceAccount

Defines the `vbr-admin` service account in the `kasten-io` namespace.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vbr-admin
  namespace: kasten-io
```

---

### 2. ClusterRoleBinding to `k10-admin`

Grants full access to the Kasten APIs via the `k10-admin` ClusterRole.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vbr-admin-k10-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k10-admin
subjects:
  - kind: ServiceAccount
    name: vbr-admin
    namespace: kasten-io
```

---

### 3. ClusterRoleBinding to `kasten-admin`

Grants additional Kasten administrative access.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vbr-admin-kasten-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kasten-admin
subjects:
  - kind: ServiceAccount
    name: vbr-admin
    namespace: kasten-io
```

---

### 4. Persistent Token Secret

Creates a `Secret` linked to the `vbr-admin` service account, resulting in a **long-lived, non-expiring token** for authentication.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vbr-admin-token
  namespace: kasten-io
  annotations:
    kubernetes.io/service-account.name: vbr-admin
type: kubernetes.io/service-account-token
```

## Usage

After applying this manifest, retrieve the token with:

```bash
kubectl -n kasten-io get secret vbr-admin-token -o jsonpath='{.data.token}' | base64 -d
```

Use this token for authenticating API calls to Kasten K10 or in external tools like Veeam VBR.

## Apply the Manifest


<details>
<summary>📦 otel-deployment.yaml</summary>

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vbr-admin
  namespace: kasten-io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vbr-admin-k10-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k10-admin
subjects:
  - kind: ServiceAccount
    name: vbr-admin
    namespace: kasten-io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vbr-admin-kasten-access
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kasten-admin
subjects:
  - kind: ServiceAccount
    name: vbr-admin
    namespace: kasten-io
---
apiVersion: v1
kind: Secret
metadata:
  name: vbr-admin-token
  namespace: kasten-io
  annotations:
    kubernetes.io/service-account.name: vbr-admin
type: kubernetes.io/service-account-token

```

</details>



```bash
kubectl apply -f vbr-admin-access.yaml
```

Ensure the Kasten K10 Helm deployment was done with `auth.mode=token` or compatible.


---
