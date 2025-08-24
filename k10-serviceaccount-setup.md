# Kasten K10 Service Account Setup

This document provides step-by-step instructions to create a ServiceAccount for Kasten K10, 
bind it with required ClusterRoles, and generate a permanent token for access.

---

## 1. Create the Service Account

```bash
kubectl create serviceaccount my-k10-sa -n kasten-io
```

---

## 2. Bind ClusterRoles

Bind the service account with `k10-admin`, `kasten-admin`, and `cluster-admin` roles.

```bash
kubectl create clusterrolebinding my-k10-sa-k10-admin   --clusterrole=k10-admin   --serviceaccount=kasten-io:my-k10-sa

kubectl create clusterrolebinding my-k10-sa-kasten-admin   --clusterrole=kasten-admin   --serviceaccount=kasten-io:my-k10-sa

kubectl create clusterrolebinding my-k10-sa-cluster-admin   --clusterrole=cluster-admin   --serviceaccount=kasten-io:my-k10-sa
```

---

## 3. Create a Permanent Token

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

---

## 4. Display the Token

Run the following command to retrieve and decode the token:

```bash
kubectl get secret my-k10-sa-token -n kasten-io -o jsonpath="{.data.token}" | base64 --decode
```

This token can then be used to log in to the K10 dashboard or API.

---
