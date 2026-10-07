-- ==============================================================================
-- BigQuery Sample Queries for GKE Log Analysis
-- Dataset: project-a910b7aa-8608-45db-9af.gke_logs_dataset
-- ==============================================================================

-- 1. Application Error Rates Over Time
-- Aggregates logs containing ERROR or Exception strings grouped by 5-minute intervals
SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE) AS log_minute,
  resource.labels.container_name AS container,
  COUNT(*) as error_count
FROM
  `project-a910b7aa-8608-45db-9af.gke_logs_dataset.stdout`
WHERE
  severity IN ('ERROR', 'CRITICAL')
  OR textPayload LIKE '%Error%'
  OR textPayload LIKE '%Exception%'
GROUP BY
  log_minute, container
ORDER BY
  log_minute DESC;

-- 2. Pod Restart Counts & Warning Events by Namespace
-- Analyzes Kubernetes cluster events for Warning/Failed scheduling/restart events
SELECT
  resource.labels.namespace_name AS namespace,
  jsonPayload.message AS event_message,
  COUNT(*) as occurrence_count
FROM
  `project-a910b7aa-8608-45db-9af.gke_logs_dataset.events`
WHERE
  jsonPayload.type = 'Warning'
  OR jsonPayload.reason LIKE '%BackOff%'
  OR jsonPayload.reason LIKE '%Failed%'
GROUP BY
  namespace, event_message
ORDER BY
  occurrence_count DESC;

-- 3. Top Log Sources by Container Volume
SELECT
  resource.labels.cluster_name AS cluster_name,
  resource.labels.container_name AS container_name,
  COUNT(*) AS total_log_entries
FROM
  `project-a910b7aa-8608-45db-9af.gke_logs_dataset.stdout`
GROUP BY
  cluster_name, container_name
ORDER BY
  total_log_entries DESC;

-- 4. Ingress / Load Balancer Latency & HTTP 5xx Status Analysis
SELECT
  httpRequest.requestMethod AS http_method,
  httpRequest.status AS status_code,
  ROUND(AVG(CAST(SUBSTR(httpRequest.latency, 1, LENGTH(httpRequest.latency)-1) AS FLOAT64)), 3) AS avg_latency_sec,
  COUNT(*) AS request_count
FROM
  `project-a910b7aa-8608-45db-9af.gke_logs_dataset.requests`
WHERE
  httpRequest.status >= 500
GROUP BY
  http_method, status_code
ORDER BY
  request_count DESC;
