# 📊 OpenTelemetry Collector for Kasten K10 → Splunk HEC Integration

This setup allows you to collect **Kasten K10** Prometheus metrics and forward them to **Splunk HEC** using an OpenTelemetry Collector sidecar. It filters and sends only K10-specific metrics (`k10_`, `jobs_`, `actions_`) to a custom Splunk index.

---

## ✅ Prerequisites

- Running Kasten K10 instance
- Splunk instance with HEC (HTTP Event Collector) enabled
- `kubectl` access to your Kubernetes cluster

---

## 📁 Step-by-Step Guide

### 1. 🔧 Create Splunk Index

Create a new index in Splunk (e.g., `k10-metrics`) with the following settings:
- **Index Name:** `k10-metrics`
- **Data Type:** Events

---

### 2. ⚙️ Configure Splunk HEC Token

From Splunk UI:

- Go to **Settings → Data Inputs → HTTP Event Collector**
- Enable global HEC settings (if disabled)
- Click **"New Token"** and configure:
  - **Name:** `otel_collector`
  - **Source Type:** `otel_metrics`
  - **Index:** `k10-metrics` (created above)
  - Save the token

> Save the token and endpoint URL for the next step.

---

### 3. 🚀 Deploy OpenTelemetry Collector

Apply the following Kubernetes manifests in the same namespace as Kasten (`kasten-io`):

> ⚠️ **Replace** the `token` and `endpoint` placeholders in the ConfigMap with your actual HEC token and Splunk HEC endpoint.

<details>
<summary>📦 otel-deployment.yaml</summary>

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: kasten-io
data:
  otel-collector-config.yaml: |
    receivers:
      prometheus:
        config:
          scrape_configs:
            - job_name: k10
              scrape_interval: 15s
              honor_labels: true
              scheme: http
              metrics_path: /k10/prometheus/federate
              params:
                'match[]':
                  - '{__name__=~"^k10_.*"}'
                  - '{__name__=~"^jobs_.*"}'
                  - '{__name__=~"^actions_.*"}'
              static_configs:
                - targets:
                    - prometheus-server.kasten-io.svc.cluster.local
                  labels:
                    app: "k10"
              metric_relabel_configs:
                - source_labels: [__name__]
                  regex: '^(k10_.*|jobs_.*|actions_.*)$'
                  action: keep

    processors:
      batch: {}

    exporters:
      splunk_hec:
        token: "****YOUR_TOKEN_HERE****"
        endpoint: "https://your-splunk-hec-endpoint:8088/services/collector"
        index: "k10-metrics"
        tls:
          insecure_skip_verify: true
        source: "otel-k10"

    service:
      pipelines:
        metrics:
          receivers: [prometheus]
          processors: [batch]
          exporters: [splunk_hec]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otel-collector
  namespace: kasten-io
  labels:
    app: otel-collector
spec:
  replicas: 1
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: otel-collector
          image: quay.io/signalfx/splunk-otel-collector:latest
          args: ["--config=/conf/otel-collector-config.yaml"]
          volumeMounts:
            - name: config-volume
              mountPath: /conf
      volumes:
        - name: config-volume
          configMap:
            name: otel-collector-config
---
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: kasten-io
spec:
  selector:
    app: otel-collector
  ports:
    - protocol: TCP
      port: 8888
      targetPort: 8888
```

</details>

Apply with:

```bash
kubectl apply -f otel-deployment.yaml
```

---

## 🔍 Validate in Splunk

Once the `otel-collector` pod is running, search in Splunk with:

```spl
index="k10-metrics" application=k10 metric_name=jobs_completed
```

---

## 🔐 Notes

- Only Kasten metrics (`k10_.*`, `jobs_.*`, `actions_.*`) are scraped and forwarded
- Exporter uses `splunk_hec` with TLS verification skipped (you may adjust this for production)
- You can scale or modify the deployment as needed

---

## 📬 Support

For issues, refer to:
- [Splunk OpenTelemetry Collector Docs](https://github.com/signalfx/splunk-otel-collector)
- [Kasten K10 Documentation](https://docs.kasten.io)