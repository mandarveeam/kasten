# Assisted Installer Deployment with Podman (Fedora)

This guide describes how to run the Assisted Installer using **Podman**
on Fedora.\
DNS is required --- without DNS the UI cannot be accessed.

------------------------------------------------------------------------

## Prerequisites

-   Fedora OS (Podman works reliably here, Ubuntu may fail for this
    setup)
-   Podman installed and running
-   Network access with proper DNS resolution

------------------------------------------------------------------------

## Pod Definition

Save the following as `pod.yml`:

``` yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: assisted-installer
  name: assisted-installer
spec:
  containers:
  - args:
    - run-postgresql
    image: quay.io/sclorg/postgresql-12-c8s:latest
    name: db
    envFrom:
    - configMapRef:
        name: config
  - image: quay.io/edge-infrastructure/assisted-installer-ui:latest
    name: ui
    ports:
    - hostPort: 8080
    envFrom:
    - configMapRef:
        name: config
  - image: quay.io/edge-infrastructure/assisted-image-service:latest
    name: image-service
    ports:
    - hostPort: 8888
    envFrom:
    - configMapRef:
        name: config
  - image: quay.io/edge-infrastructure/assisted-service:latest
    name: service
    ports:
    - hostPort: 8090
    envFrom:
    - configMapRef:
        name: config
  restartPolicy: Never
```

------------------------------------------------------------------------

## ConfigMap

Save the following as `configmap.yml`:

``` yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
data:
  ASSISTED_SERVICE_HOST: 192.168.1.30:8090
  ASSISTED_SERVICE_SCHEME: http
  AUTH_TYPE: none
  DB_HOST: 127.0.0.1
  DB_NAME: installer
  DB_PASS: admin
  DB_PORT: "5432"
  DB_USER: admin
  DEPLOY_TARGET: onprem
  DEPLOYMENT_TYPE: "Podman"
  DISK_ENCRYPTION_SUPPORT: "true"
  DUMMY_IGNITION: "false"
  ENABLE_SINGLE_NODE_DNSMASQ: "true"
  HW_VALIDATOR_REQUIREMENTS: '[{"version":"default","master":{"cpu_cores":4,"ram_mib":16384,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10,"network_latency_threshold_ms":100,"packet_loss_percentage":0},"arbiter":{"cpu_cores":2,"ram_mib":8192,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10,"network_latency_threshold_ms":1000,"packet_loss_percentage":0},"worker":{"cpu_cores":2,"ram_mib":8192,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10,"network_latency_threshold_ms":1000,"packet_loss_percentage":10},"sno":{"cpu_cores":8,"ram_mib":16384,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10},"edge-worker":{"cpu_cores":2,"ram_mib":8192,"disk_size_gb":15,"installation_disk_speed_threshold_ms":10}}]'
  IMAGE_SERVICE_BASE_URL: http://192.168.1.30:8888
  IPV6_SUPPORT: "true"
  ISO_IMAGE_TYPE: "full-iso"
  LISTEN_PORT: "8888"
  NTP_DEFAULT_SERVER: ""
  OS_IMAGES: '[{"openshift_version":"4.18","cpu_architecture":"x86_64","url":"https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/4.18/4.18.1/rhcos-4.18.1-x86_64-live.x86_64.iso","version":"418.94.202501221327-0"}]'
  POSTGRESQL_DATABASE: installer
  POSTGRESQL_PASSWORD: admin
  POSTGRESQL_USER: admin
  PUBLIC_CONTAINER_REGISTRIES: 'quay.io,registry.ci.openshift.org'
  RELEASE_IMAGES: '[{"openshift_version":"4.18","cpu_architecture":"x86_64","cpu_architectures":["x86_64"],"url":"quay.io/openshift-release-dev/ocp-release:4.18.23-x86_64","version":"4.18.23"}]'
  SERVICE_BASE_URL: http://192.168.1.30:8090
  STORAGE: filesystem
  ENABLE_UPGRADE_AGENT: "true"
  AIUI_CHAT_API_URL: http://localhost:12121
```

------------------------------------------------------------------------

## Deploying with Podman

Run the pod using:

``` bash
podman start kube --configmap configmap.yml pod.yml
```

Once running, access the **UI** on port **8080**.

------------------------------------------------------------------------

## Image Generation

After creating a cluster and adding a host in the UI:

-   Click **Download Image**
-   It will take \~30 minutes to download and generate the ISO.

Monitor image size growth:

``` bash
watch -n10 'podman exec -it assisted-installer-image-service du -sh /data/'
```

List the generated ISOs:

``` bash
podman exec -it assisted-installer-image-service ls -ltrh /data/
```

Example output:

    total 1.4G
    -rw-------. 1 1001 root 1.2G Sep 18 15:12 rhcos-full-iso-4.18-418.94.202501221327-0-x86_64.iso
    -rwxr-xr-x. 1 1001 root 4.4M Sep 18 15:12 nmstatectl-4.18-418.94.202501221327-0-x86_64
    -rw-r--r--. 1 1001 root 113M Sep 19 03:29 rhcos-minimal-iso-4.18-418.94.202501221327-0-x86_64.iso

You can copy these ISO files from the container to the host as needed.

------------------------------------------------------------------------

## VM Requirements

When creating a VM with the generated ISO, allocate at least:

-   **16 vCPUs**
-   **32 GB RAM**

Anything less may fail.

------------------------------------------------------------------------

## Retrieve Kubeadmin Password

List cluster data:

``` bash
podman exec -it assisted-installer-service ls -ltrh /data/<CLUSTER_ID>
```

Example files:

    -rw-------. 1 1001 root   23 Sep 18 16:04 manifests
    -rw-------. 1 1001 root 306K Sep 18 16:07 bootstrap.ign
    -rw-------. 1 1001 root  393 Sep 18 16:07 master.ign
    -rw-------. 1 1001 root  134 Sep 18 16:07 metadata.json
    -rw-------. 1 1001 root  393 Sep 18 16:07 worker.ign
    -rw-------. 1 1001 root 8.8K Sep 18 16:07 kubeconfig-noingress
    -rw-------. 1 1001 root   23 Sep 18 16:07 kubeadmin-password
    -rw-------. 1 1001 root 3.9K Sep 18 16:07 install-config.yaml

Retrieve the kubeadmin password:

``` bash
podman exec -it assisted-installer-service cat /data/<CLUSTER_ID>/kubeadmin-password
```

------------------------------------------------------------------------

## Summary

-   Use Fedora with Podman for reliability\
-   UI available on port **8080**\
-   ISO generation takes \~30 minutes\
-   Ensure sufficient VM resources\
-   Retrieve kubeadmin password from container

This completes the Assisted Installer deployment with Podman.
