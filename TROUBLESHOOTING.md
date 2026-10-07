# GCP E2E Multi-Cluster Project: Troubleshooting Scenario

## Scenario Overview
During the initial deployment of **Web Application A** behind a LoadBalancer service in the GKE `us-central1` cluster (`gke-primary`), the Kubernetes service failed to route external HTTP traffic to the pods. Requests timed out with HTTP 502 Bad Gateway responses at the Google Cloud Ingress endpoint.

---

## 1. Symptom & Initial Detection
- **Symptom:** External curl requests to the LoadBalancer public IP (`http://34.135.x.x`) returned `HTTP 502 Bad Gateway`.
- **Observation:** Running `kubectl get pods` showed all 3 replicas of `web-app-a` in `Running` state, but the LoadBalancer Network Endpoint Group (NEG) reported `UNHEALTHY` backends in GCP Console.

---

## 2. Root Cause Analysis (Step-by-Step Investigation)

### Step 1: Check Pod Status & Container Logs
```bash
kubectl get pods -l app=web-app-a
kubectl logs -l app=web-app-a --tail=50
```
*Result:* Containers were running fine and producing standard startup logs. No application exceptions were found.

### Step 2: Inspect Kubernetes Service & NEG Annotations
```bash
kubectl describe svc web-app-a-service
```
*Result:* Found that the standalone NEG annotation `cloud.google.com/neg: '{"ingress": true}'` was auto-injected by GKE, but container target ports were misaligned.

### Step 3: Check GCP Cloud Armor & Firewall Logs
```bash
gcloud compute firewall-rules list --filter="network=gcp-e2e-vpc"
```
*Result:* The auto-generated GCP Load Balancer firewall rule allowing GCP health check probe IPs (`130.211.0.0/22` and `35.191.0.0/16`) to reach GKE node ports was missing or blocked due to VPC firewall default-deny egress/ingress rules.

---

## 3. Resolution Steps

### Fix 1: Update Health Checks & Service Port Definitions
Aligned container port `80` with the LoadBalancer service `targetPort` and added explicit readiness/liveness probes in `app-a.yaml`:

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Fix 2: Explicitly Allow GCP Health Check Ranges in Firewall
Added a firewall rule via Terraform allowing GCP health checkers to hit GKE nodes:

```hcl
resource "google_compute_firewall" "allow_gcp_health_checks" {
  name    = "allow-gcp-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "3000", "8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-node"]
}
```

---

## 4. Verification & Prevention
1. Re-applied Kubernetes manifests and verified backend health:
   ```bash
   kubectl get endpoints web-app-a-service
   ```
2. Tested endpoint connectivity:
   ```bash
   curl -I http://<EXTERNAL-IP>
   # Returns HTTP/1.1 200 OK
   ```
3. **Prevention Lesson:** Always ensure GCP Health Check ranges (`130.211.0.0/22` and `35.191.0.0/16`) are permitted in custom VPC firewall rules when deploying GKE services with NEGs or GCP External HTTPS Load Balancers.
