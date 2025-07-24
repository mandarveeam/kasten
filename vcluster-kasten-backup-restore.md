
# Kasten K10 Backup and Restore Testing for vcluster

## Objective
To validate the backup and restore capabilities of Kasten K10 for **virtual clusters (vcluster)** with a focus on:
- Full namespace restore (including PVC data and vcluster objects)
- PVC-only restore (data restore without app redeployment)
- Restore to alternate volumes
- Operational readiness of restored workloads

---

## Test Environment Overview

### vcluster Deployment
Two vclusters were created using Loft/vcluster in different host namespaces:

```bash
vcluster list
```

| NAME | NAMESPACE | STATUS  | VERSION | CONNECTED | AGE      |
|------|-----------|---------|---------|-----------|----------|
| cl2  | b         | Running | 0.26.0  |           | 1h57m5s  |
| cl1  | a         | Running | 0.26.0  |           | 1h23m1s  |

### Workload Description
A sample application with a PersistentVolumeClaim (PVC) was deployed inside **vcluster `cl1`** within the virtual namespace **`a`**.

---

## Test Cases and Observations

### ✅ Test 1: Full vcluster Backup and Restore (Namespace + Data)

**Steps:**
1. Created a backup in Kasten targeting:
   - Namespace: `a`
   - vcluster-specific resources (CRDs, configmaps, secrets, workloads)
   - PVC and associated volume data
2. Deleted vcluster `cl1` (namespace `a`)
3. Restored the backup in Kasten, targeting the same namespace `a`
4. Monitored for:
   - Re-creation of all objects
   - PVCs reattached
   - Pods and services running

**Outcome:**  
✅ Success  
The vcluster `cl1` was fully restored, including the workload and data. All services resumed normally.

---

### ❌ Test 2: Data-Only Restore after Deployment Scaled to 0

**Scenario:**
Evaluating partial restore functionality—only PVC data—without redeploying the workload.

**Steps:**
1. Scaled down the deployment in vcluster `cl1` (namespace `a`) to 0 replicas.
2. Initiated a **PVC-only restore** via Kasten targeting the volume from the previous backup.
3. Observed that the volume was no longer bound and the pods failed to start upon scaling.

**Outcome:**  
❌ Failed  
PVC was not re-attached properly, likely due to the lack of workload (Deployment) present in the cluster to claim the volume. Restoration of PVC alone is insufficient unless the workload is recreated or retained.

**Insight:**  
This highlights the tight coupling between workloads and PVCs in Kubernetes. PVC-only restore is viable for data extraction or manual reattachment, but not for application rehydration.

---

### ✅ Test 3: Pause vcluster → Restore Namespace → Resume

**Scenario:**
Evaluating restoration into a paused vcluster environment to test compatibility with lifecycle management.

**Steps:**
1. Paused vcluster `cl1`.
2. Restored namespace `a` using Kasten backup (including app + PVC).
3. Resumed the vcluster.

**Outcome:**  
✅ Success  
Restoration completed successfully. Upon resume, all services became operational. This confirms that vclusters can be safely paused for restores, allowing non-disruptive DR workflows.

---

### ✅ Test 4: Volume-Clone-Restore to Alternate PVC

**Scenario:**
Restore only the data to a new volume for forensic inspection or cross-environment recovery.

**Steps:**
1. Initiated **volume clone restore** from Kasten UI.
2. Targeted the same namespace (`a`), but renamed the PVC.
3. Launched a temporary BusyBox pod and mounted the restored PVC.
4. Validated presence of expected data under `/data/db`.

**Outcome:**  
✅ Success  
Data was restored to an alternate PVC successfully. Useful for:
- Data recovery in parallel environments
- Extracting logs or artifacts without disturbing original workloads

---

## Summary of Test Results

| Test Scenario                                   | Description                                               | Result  |
|------------------------------------------------|-----------------------------------------------------------|---------|
| Full vcluster + data restore                   | Restore full vcluster including PVC and workloads         | ✅ Success |
| PVC-only restore post deployment scale to 0    | Restore only volume without workloads                     | ❌ Failed |
| Pause → Restore → Resume                       | Validate vcluster pause compatibility with restore        | ✅ Success |
| Volume Clone Restore to new PVC                | Restore data to alternate volume for inspection/extract   | ✅ Success |

---

## Conclusions & Recommendations

1. **Kasten works seamlessly for full vcluster restores**, provided the correct namespace and resources are targeted.
2. **PVC-only restores should be used cautiously.** They are ideal for forensic recovery but not for workload continuity.
3. **vcluster lifecycle (pause/resume)** does not interfere with Kasten backup/restore flows, offering flexibility during DR.
4. **Volume Clone Restore** is a powerful tool for:
   - Testing
   - Validation
   - Non-intrusive recovery
   - Data extraction in secure environments

---

## Next Steps

- Automate vcluster backup + restore with GitOps or CI/CD pipelines.
- Add backup policies to trigger based on resource creation or changes.
- Explore restoring vclusters to different host clusters for cross-cluster DR.
