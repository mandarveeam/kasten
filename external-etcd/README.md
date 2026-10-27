# etcd Backup & Restore with Veeam Kasten

A Kanister blueprint and Kasten policy that back up an **external, systemd-managed etcd** member to a Kasten location profile (S3), and restore it on demand.

| File | Purpose |
|---|---|
| `etcd-blueprint.yaml` | Kanister Blueprint with `backup`, `restore` and `delete` actions |
| `etcd-backup-policy.yaml` | Kasten Policy (`test`) that runs the backup on demand |
| `etcd-details-secret.example.yaml` | Template for the `etcd-details` Secret the blueprint reads (placeholders only) |

## How it works

Kasten can't reach etcd directly, so the blueprint is attached to a Secret that holds the etcd connection details. The policy selects the `etcd-backup` namespace and filters to resources labelled `include=true`, which is the `etcd-details` Secret. Because the Secret carries the annotation `kanister.kasten.io/blueprint: etcd-blueprint`, Kasten runs the blueprint's actions with the Secret available to the templates as `.Object`.

```
Policy "test" ──selects──▶ Secret etcd-details   (label include=true,
                                                   annotation kanister.kasten.io/blueprint=etcd-blueprint)
                                   │
                                   ▼
                          etcd-blueprint (KubeTask pod)
        backup:  download etcdctl ─▶ snapshot save ─▶ gzip ─▶ kando push ─▶ S3 profile
        restore: kando pull ─▶ ssh copy to host ─▶ stop etcd ─▶ restore to new data-dir
                 ─▶ repoint systemd unit ─▶ start ─▶ health check
        delete:  kando delete (when a restore point is retired)
```

### Backup

The backup pod installs `tar` and `gzip` with `microdnf`, then downloads etcdctl v3.5.9 (linux-amd64) from GitHub. It writes the CA, client cert and key from the Secret to `/tmp` and runs `etcdctl snapshot save` against `endpoints`. Finally it gzips the snapshot and uploads it with `kando location push` to:

```
etcd_backups/<namespace>/<backup-time>/etcd-backup.db.gz
```

That path is saved in the restore point as the artifact `cloudObject.backupLocation`.

### Restore

The restore pod installs `openssh-clients`, pulls the snapshot for the chosen restore point, unzips it, and streams it to the etcd host over plain `ssh ... 'cat > file'`. It deliberately avoids `scp`/SFTP, which fails on hosts without the sftp subsystem, such as some GCP OS Login setups.

It then runs a script on the host over SSH:

1. **Discover the live configuration.** It finds the running `etcd` process and reads its flags from `/proc/<pid>/cmdline`: `--name`, `--data-dir`, `--initial-cluster`, `--initial-advertise-peer-urls`, `--listen-client-urls` and the TLS file paths.
2. **Find the service.** It looks for the systemd unit whose name contains `etcd` (falling back to `etcd.service`) and the `User=`/`Group=` it runs as.
3. **Stop etcd and restore the snapshot into a new directory.** It stops the service and runs `etcdctl snapshot restore` into `<data-dir>-restored-<timestamp>` with a fresh cluster token. The new directory is then `chown`ed to the service user.
4. **Repoint the service.** It backs up the unit file to `<unit>.bak.<timestamp>`, then uses `sed` to point `--data-dir=` (and `--initial-cluster-token=`) at the new directory.
5. **Start and check.** It runs `daemon-reload`, starts the service, waits 5 seconds, and runs `etcdctl endpoint health`.

The original data-dir is never modified or deleted.

### Delete

When Kasten retires a restore point, `kando location delete` removes its snapshot object from the profile.

## Prerequisites

**Kubernetes/Kasten side**
- Veeam Kasten in `kasten-io`.
- A location profile named `s3`.
- Pods in `etcd-backup` can reach the etcd client port (2379) and SSH (22) on the etcd host.
- Outbound internet access for `microdnf` and the GitHub etcd download.

**etcd host**

| Requirement | Why |
|---|---|
| etcd runs as a systemd service | The service is stopped, started and repointed through systemd |
| `--data-dir=` (with `=`) is in the unit file's `ExecStart` | The `sed` repoint looks for that exact form |
| etcd is **running** when the restore starts | Its configuration is read from the live process |
| SSH user has **passwordless sudo** | Used for `systemctl`, `etcdctl`, `chown`, `cp` and `sed` |
| `etcdctl` is on the PATH that `sudo` uses | The restore and health check call it as plain `sudo etcdctl` |
| x86_64 (amd64) | Backup downloads the amd64 etcdctl build |

## Setup

### 1. Create the Secret

Create it from local files so no credentials are written into YAML (key names must match exactly):

```bash
oc create namespace etcd-backup

oc -n etcd-backup create secret generic etcd-details \
  --from-literal=endpoints=https://<ETCD_IP>:2379 \
  --from-file=cacert=./ca.crt \
  --from-file=cert=./client.crt \
  --from-file=key=./client.key \
  --from-literal=ssh_host=<ETCD_IP> \
  --from-literal=ssh_user=<SSH_USER> \
  --from-file=sshkey=./id_rsa

oc -n etcd-backup label secret etcd-details include=true
oc -n etcd-backup annotate secret etcd-details kanister.kasten.io/blueprint=etcd-blueprint
```

Alternatively, fill in `etcd-details-secret.example.yaml` and `oc apply` it. Don't commit the filled-in copy.

| Key | Used by | Value |
|---|---|---|
| `endpoints` | backup | etcd client URL, e.g. `https://192.168.122.215:2379` (single endpoint) |
| `cacert` | backup | etcd CA certificate (PEM) |
| `cert` | backup | etcd client certificate (PEM) |
| `key` | backup | etcd client key (PEM) |
| `ssh_host` | restore | etcd host IP or name |
| `ssh_user` | restore | SSH user with passwordless sudo |
| `sshkey` | restore | Private key for `ssh_user` |

### 2. Apply the blueprint and policy

```bash
oc apply -f etcd-blueprint.yaml
oc apply -f etcd-backup-policy.yaml
```

## Adapting this for another environment

The defaults in these files match the original environment. Before using them elsewhere, review the values below. Several values are linked, so a change in one file has to be mirrored in another.

### Values that must match across files

| Value | Default | Where it appears | Keep in sync with |
|---|---|---|---|
| Application namespace | `etcd-backup` | Policy `spec.selector...values`; Secret `metadata.namespace` | Both must name the same namespace |
| Blueprint name | `etcd-blueprint` | Blueprint `metadata.name`; Secret annotation `kanister.kasten.io/blueprint` | Annotation value must equal the blueprint name |
| Selection label | `include: "true"` | Policy `includeResources.matchExpressions` (key `include`, value `"true"`); Secret `metadata.labels` | Label key and value must match exactly |
| Kasten namespace | `kasten-io` | Blueprint `metadata.namespace`; Policy `metadata.namespace`; Policy `profile.namespace` | Must be the namespace Kasten is installed in |
| Location profile | `s3` | Policy `backupParameters.profile.name` | Must be an existing location profile in the Kasten namespace |

If you rename the label, choose a key/value that no other resource in the namespace uses; otherwise those resources are picked up by the policy too.

### Values that are environment-specific

| Value | Default | Where | When to change |
|---|---|---|---|
| Policy name | `test` | Policy `metadata.name` | Recommended: use a descriptive name such as `etcd-backup-policy`. Applying under a new name creates a new policy; it doesn't rename the old one. |
| Backup frequency | `@onDemand` | Policy `spec.frequency` | For schedules, use e.g. `@daily` **and** uncomment `retention` (required for scheduled policies) |
| etcdctl version | `v3.5.9` | Blueprint backup script, `ETCD_VER=v3.5.9` | Match (or stay compatible with) your etcd server version |
| CPU architecture | `amd64` | Blueprint backup script, download URL `...-linux-amd64.tar.gz` | Change to `arm64` etc. if your Kubernetes nodes aren't x86_64. Note the extracted folder name in the `chmod` and `etcdctl` lines changes too. |
| Download timeout | `--max-time 30` | Blueprint backup script, `curl` line | Increase on slow links |
| Download source | GitHub releases URL | Blueprint backup script, `curl` line | Point to an internal mirror in air-gapped clusters |
| Kanister image | `ghcr.io/kanisterio/kanister-kubectl-1.18:0.119.0` | Blueprint, `image:` in all three phases | Use an image that matches your Kanister/Kasten version, or a mirrored copy. It must contain `kando` and `microdnf`. |
| Restore start wait | `sleep 5` | Blueprint restore script, before `endpoint health` | Increase if etcd takes longer to become healthy |

### Values that come from the Secret (no YAML edits needed)

The etcd endpoint, TLS certificates, SSH host, SSH user and SSH key are all read from the Secret at run time. For a new etcd cluster, create a new Secret with that cluster's values (see [Setup](#setup)); the blueprint itself doesn't need changes for these.

### Checklist for a new environment

1. Confirm the etcd host meets the [prerequisites](#prerequisites). In particular, check that the unit file uses `--data-dir=...` and that `sudo etcdctl` works for the SSH user.
2. Confirm the location profile exists:
   ```bash
   oc get profiles.config.kio.kasten.io -n kasten-io
   ```
3. Update the namespace, label, profile and policy name in the YAMLs, keeping the linked values in sync.
4. Create the Secret with the label and annotation, then apply the blueprint and policy.
5. Run one on-demand backup and check that the object appears in the bucket under `etcd_backups/<namespace>/`.
6. Test a restore in a non-production environment before relying on it.

## Running a backup

In the Kasten dashboard, go to **Policies → test → Run Once**. Or from the CLI:

```bash
cat <<EOF | oc create -f -
apiVersion: actions.kio.kasten.io/v1alpha1
kind: RunAction
metadata:
  generateName: run-test-
  namespace: kasten-io
spec:
  subject:
    kind: Policy
    name: test
    namespace: kasten-io
EOF
```

Watch the job pod with `oc -n etcd-backup get pods -w`.

For scheduled backups, set `frequency` in the policy (for example `@daily`) and uncomment the `retention` block. Kasten calls the `delete` action as restore points expire.

## Restoring

In the Kasten dashboard, open **Applications → etcd-backup → Restore**, choose a restore point, and restore into the same namespace. Kasten restores the Secret and then runs the blueprint's `restore` action.

> ⚠️ The restore stops etcd and brings it back with the snapshot's data. Writes made after the snapshot was taken are lost, and anything depending on etcd is unavailable during the restore.

## Rolling back a restore

The pre-restore data-dir and unit file are both kept, so on the etcd host:

```bash
sudo systemctl stop etcd                                   # use the actual unit name
sudo cp <unit-file>.bak.<timestamp> <unit-file>            # path is printed by: systemctl show -p FragmentPath etcd
sudo systemctl daemon-reload
sudo systemctl start etcd
```

After a successful restore, you can delete the old data-dir and the `.bak.*` unit files once you no longer need them.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `microdnf` or `curl` fails or times out | No internet from the pod. The download has `--max-time 30`; slow links may need a higher value. |
| `context deadline exceeded` on snapshot | Pod can't reach `endpoints`, or the TLS material doesn't match. |
| `Permission denied (publickey)` | `sshkey` doesn't match `ssh_user`'s `authorized_keys`. |
| `sudo: a password is required` | Configure passwordless sudo for `ssh_user`. |
| `no running etcd process found` | etcd must be running when the restore starts. |
| `sudo: etcdctl: command not found` | `etcdctl` isn't in sudo's `secure_path`. Symlink it into `/usr/bin` or add its directory to `secure_path`. |
| Restore completes but etcd still serves old data | `--data-dir` isn't written as `--data-dir=...` in the unit file (for example, it's set via an env file), so `sed` changed nothing. |
| `endpoint health` fails right after start | 5 seconds was too short. Check `systemctl status etcd` and `journalctl -u etcd`. |

## Security notes

The Secret contains etcd client credentials and an SSH key with sudo rights, and Kasten stores a copy of it in each restore point, so restrict access to the namespace and to restore points. Keep real Secret values out of Git.

`set -x` is commented out in the backup and restore scripts because it printed the decoded keys and the S3 profile credentials into the job logs. Uncomment it temporarily if you need to debug.

SSH uses `StrictHostKeyChecking=no`, which works but skips host key verification.

## Limitations

This setup targets a **single etcd member on amd64**. It uses one endpoint for backup and one `ssh_host` for restore. A multi-member cluster would need every member restored together. Each restore leaves an extra data-dir and unit backup on the host. kubeadm static-pod etcd and managed control planes are not supported.
