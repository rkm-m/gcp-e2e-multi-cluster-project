# GCP End-to-End Multi-Cluster GKE Architecture

## Overview
This repository contains the Infrastructure as Code (Terraform), Kubernetes manifests, BigQuery log analysis queries, Grafana dashboards, and deployment guides for an enterprise-grade GCP multi-cluster application architecture.

```
                         ┌───────────────────────────┐
                         │   Global Cloud DNS / LB   │
                         └─────────────┬─────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
  ┌───────────────────────────┐                 ┌───────────────────────────┐
  │   GKE Primary Cluster     │                 │   GKE Secondary Cluster   │
  │   Region: us-central1     │                 │   Region: us-east1        │
  │  ┌─────────────────────┐  │                 │  ┌─────────────────────┐  │
  │  │ Web App A (3 pods)  │  │                 │  │ Web App A (3 pods)  │  │
  │  └─────────────────────┘  │                 │  └─────────────────────┘  │
  │  ┌─────────────────────┐  │                 │  ┌─────────────────────┐  │
  │  │ Web App B (2 pods)  │  │                 │  │ Web App B (2 pods)  │  │
  │  └─────────────────────┘  │                 │  └─────────────────────┘  │
  └─────────────┬─────────────┘                 └─────────────┬─────────────┘
                │                                             │
                └──────────────────────┬──────────────────────┘
                                       ▼
                         ┌───────────────────────────┐
                         │  Cloud Logging Sink       │
                         └─────────────┬─────────────┘
                                       ▼
                         ┌───────────────────────────┐
                         │  BigQuery Log Dataset     │
                         └─────────────┬─────────────┘
                                       ▼
                         ┌───────────────────────────┐
                         │    Grafana Dashboard      │
                         └─────────────┬─────────────┘
```

---

## Deliverables & Project Assessment

| Deliverable | Description | File Location |
|---|---|---|
| **IaC Code** | Modular Terraform configuration for GCP VPC, Cloud NAT, GKE Clusters, BigQuery Sink | `terraform/` |
| **App Deployment** | Kubernetes manifests for Web App A & Web App B (HPA, Services, Pods) | `k8s/` |
| **BigQuery Queries** | Sample log analysis queries for application error rates, latencies, and pod events | `observability/bigquery_queries.sql` |
| **Grafana Dashboard** | Complete JSON dashboard configuration (4 required panels) | `observability/grafana_dashboard.json` |
| **Troubleshooting Write-up** | Real-world scenario documenting an issue and resolution | `TROUBLESHOOTING.md` |

---

## Quick Start / Deployment Instructions

### Prerequisites
- GCP Account with billing enabled
- `gcloud` CLI installed (`gcloud auth login` and `gcloud auth application-default login`)
- `terraform` (v1.3+)
- `kubectl`

### Step 1: Set GCP Project Context
```bash
gcloud config set project project-a910b7aa-8608-45db-9af
```

### Step 2: Deploy Infrastructure via Terraform
```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 3: Connect to GKE Clusters & Deploy Applications
```bash
# Get credentials for Primary Cluster (us-central1)
gcloud container clusters get-credentials gke-primary --region us-central1 --project project-a910b7aa-8608-45db-9af

# Deploy apps to Primary Cluster
kubectl apply -f ../k8s/

# Get credentials for Secondary Cluster (us-east1)
gcloud container clusters get-credentials gke-secondary --region us-east1 --project project-a910b7aa-8608-45db-9af

# Deploy apps to Secondary Cluster
kubectl apply -f ../k8s/
```

### Step 4: Verify Accessible Application Endpoints
```bash
kubectl get svc -w
# Copy the EXTERNAL-IP for web-app-a-service and web-app-b-service and test in browser:
# http://<EXTERNAL-IP>
```
