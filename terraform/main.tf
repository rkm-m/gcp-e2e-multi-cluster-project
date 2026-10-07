terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.80.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.primary_region
}

# Variable Definitions
variable "project_id" {
  description = "The GCP Project ID"
  type        = string
  default     = "project-a910b7aa-8608-45db-9af"
}

variable "primary_region" {
  description = "Primary GKE Cluster Zone"
  type        = string
  default     = "us-central1-a"
}

variable "secondary_region" {
  description = "Secondary GKE Cluster Zone"
  type        = string
  default     = "us-east1-b"
}

# 1. Enable Required GCP APIs
resource "google_project_service" "gcp_services" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
    "servicenetworking.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# 2. VPC Network & Subnets
resource "google_compute_network" "vpc" {
  name                    = "gcp-e2e-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.gcp_services]
}

# Primary Subnet (us-central1)
resource "google_compute_subnetwork" "subnet_primary" {
  name          = "gke-primary-subnet"
  ip_cidr_range = "10.10.0.0/20"
  region        = "us-central1"
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods-primary"
    ip_cidr_range = "10.20.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services-primary"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# Secondary Subnet (us-east1)
resource "google_compute_subnetwork" "subnet_secondary" {
  name          = "gke-secondary-subnet"
  ip_cidr_range = "10.40.0.0/20"
  region        = "us-east1"
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pods-secondary"
    ip_cidr_range = "10.50.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services-secondary"
    ip_cidr_range = "10.60.0.0/20"
  }
}

# 3. Cloud Router & Cloud NAT for Internet Egress
resource "google_compute_router" "router_primary" {
  name    = "router-primary"
  region  = "us-central1"
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat_primary" {
  name                               = "nat-primary"
  router                             = google_compute_router.router_primary.name
  region                             = "us-central1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# 4. GKE Primary Cluster (us-central1)
resource "google_container_cluster" "primary" {
  name                     = "gke-primary"
  location                 = var.primary_region
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet_primary.name
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-primary"
    services_secondary_range_name = "services-primary"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "default-pool"
  location   = var.primary_region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = false
    machine_type = "e2-medium"
    disk_size_gb = 100
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append"
    ]
  }
}

# 5. GKE Secondary Cluster (us-east1)
resource "google_container_cluster" "secondary" {
  name                     = "gke-secondary"
  location                 = var.secondary_region
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet_secondary.name
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-secondary"
    services_secondary_range_name = "services-secondary"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "secondary_nodes" {
  name       = "default-pool"
  location   = var.secondary_region
  cluster    = google_container_cluster.secondary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    disk_size_gb = 100
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# 6. BigQuery Dataset & Centralized Logging Sink
resource "google_bigquery_dataset" "gke_logs_dataset" {
  dataset_id                  = "gke_logs_dataset"
  friendly_name               = "GKE Application and Infrastructure Logs"
  description                 = "Dataset receiving exported GKE container logs from Cloud Logging"
  location                    = "US"
  default_table_expiration_ms = 2592000000 # 30 days
}

resource "google_logging_project_sink" "bq_log_sink" {
  name        = "gke-bigquery-log-sink"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.gke_logs_dataset.dataset_id}"
  filter      = "resource.type=\"k8s_container\" OR resource.type=\"gke_cluster\""

  unique_writer_identity = true
}

# Grant BigQuery Data Editor permissions to the Cloud Logging Sink service account
resource "google_bigquery_dataset_access" "sink_bq_access" {
  dataset_id    = google_bigquery_dataset.gke_logs_dataset.dataset_id
  role          = "WRITER"
  user_by_email = replace(google_logging_project_sink.bq_log_sink.writer_identity, "serviceAccount:", "")
}

# Outputs
output "primary_cluster_name" {
  value = google_container_cluster.primary.name
}

output "secondary_cluster_name" {
  value = google_container_cluster.secondary.name
}

output "bigquery_dataset_id" {
  value = google_bigquery_dataset.gke_logs_dataset.dataset_id
}
