# Xander Project Detail

## What This Project Does

Xander is a local Kubernetes telemetry demo. It collects pod/container metrics, stores them in SQLite, shows live charts in Streamlit, builds simple aggregations, derives lightweight context, and lets a small rule-based agent answer cluster questions.

The current dashboard shows CPU, memory, disk I/O, network I/O, process counts, 1-minute/5-minute aggregates, context summary, and agent responses.

## Architecture

- **Telemetry Collector**: Go service in `telemetry-collector/`
  - Discovers pods through kubelet/Kubernetes access.
  - Reads cgroup metrics for CPU, memory, disk, process, and network stats.
  - Stores samples in SQLite at `/tmp/metrics.db` inside the collector pod.

- **Streamlit Dashboard**: Python app in `streamlit_app.py`
  - Copies the collector DB from the pod to `/tmp/collector-metrics.db`.
  - Reads SQLite data and renders live charts.
  - Converts raw counters into readable units like cores, MiB, MiB/s, and KiB/s.

- **Aggregation + Context**: Python functions inside `streamlit_app.py`
  - Builds 1-minute and 5-minute aggregate views.
  - Detects simple CPU-related issues and creates a context summary.

- **Agent**: Rule-based logic inside `streamlit_app.py`
  - Answers queries like `summary`, `issues`, and `explain <pod>`.
  - Uses the latest context from recent aggregates.

- **Telemetry API**: Go service in `telemetry-api/`
  - Optional API layer for endpoints like top risk, incidents, and cluster summary.

## Workflow

1. Deploy or run the Go collector in the Kubernetes cluster.
2. Collector discovers pods and reads container metrics from cgroups/procfs.
3. Collector writes metrics into SQLite.
4. Streamlit copies the collector DB locally.
5. Streamlit refreshes live charts from the local DB snapshot.
6. Aggregation builds recent pod summaries.
7. Context and agent use those summaries to answer questions.

## What We Used

- **Go**: collector, cgroup/procfs readers, SQLite storage, optional telemetry API.
- **SQLite**: local metrics database.
- **Kubernetes/kind**: local cluster and DaemonSet deployment.
- **Streamlit**: interactive dashboard and controls.
- **Pandas**: data loading, unit conversion, aggregation.
- **Altair**: live telemetry charts.
- **kubectl**: copying the collector DB and checking cluster resources.

## Setup From Fresh Clone

A helper script is provided for first-time setup:

```bash
chmod +x start-proj.sh
./start-proj.sh
```

The script checks/installs common prerequisites, creates `.venv`, installs Python dependencies, downloads Go modules, creates a kind cluster if needed, builds the collector image, loads it into kind, and deploys the collector DaemonSet.

After it finishes, run:

```bash
source .venv/bin/activate
streamlit run streamlit_app.py
```

Manual setup is below in case the script cannot install packages on your OS.

Install system tools:

```bash
# Arch example
sudo pacman -S python python-pip go docker kubectl kind sqlite
```

For Ubuntu/Debian, install equivalent packages: Python 3, pip, Go, Docker, kubectl, kind, and sqlite3.

Create and activate a Python environment:

```bash
python -m venv .venv
source .venv/bin/activate
```

Install Streamlit dashboard dependencies:

```bash
pip install streamlit pandas numpy altair requests
```

Optional agent package dependencies:

```bash
pip install -r agent/requirements.txt
```

Download Go dependencies:

```bash
cd telemetry-collector && go mod download && cd ..
cd telemetry-api && go mod download && cd ..
cd aggregation-engine && go mod download && cd ..
cd context-engine && go mod download && cd ..
```

Start Docker if it is not already running:

```bash
sudo systemctl start docker
```

Create a local kind cluster if needed:

```bash
kind create cluster --name kind
kubectl cluster-info
```

Build and deploy the collector:

```bash
cd telemetry-collector
docker build -t telemetry-collector:latest -f Dockerfile .
kind load docker-image telemetry-collector:latest --name kind
kubectl apply -f k8s/deployment.yaml
kubectl rollout status daemonset/telemetry-collector -n telemetry-system
cd ..
```

If you change collector code later, rebuild, reload, and restart:

```bash
cd telemetry-collector
docker build -t telemetry-collector:latest -f Dockerfile .
kind load docker-image telemetry-collector:latest --name kind
kubectl rollout restart daemonset/telemetry-collector -n telemetry-system
kubectl rollout status daemonset/telemetry-collector -n telemetry-system
cd ..
```

## Testing Streamlit

1. Bootstrap the project:

   ```bash
   ./start-proj.sh
   ```

2. Start or confirm the Kubernetes cluster is running:

   ```bash
   kubectl get pods -A
   ```

3. Confirm the collector pod is running:

   ```bash
   kubectl get pods -n telemetry-system -l app=telemetry-collector
   ```

4. Run the Streamlit app from the repo root:

   ```bash
   source .venv/bin/activate
   streamlit run streamlit_app.py
   ```

5. In the sidebar:
   - Select `/tmp/collector-metrics.db`.
   - Keep **Collector running** enabled.
   - Keep **Live charts** enabled.
   - Click **Refresh collector DB** once if charts start empty.

6. Check that charts update over time:
   - CPU should show cores.
   - Memory should show MiB.
   - Disk should show MiB/s.
   - Network should show KiB/s.

7. Test the agent with:

   ```text
   summary
   issues
   explain pod-y-db
   ```

## Quick Checks

Run collector tests:

```bash
cd telemetry-collector
GOCACHE=/tmp/go-cache go test ./...
```

Check the copied metrics DB:

```bash
sqlite3 /tmp/collector-metrics.db 'select count(*), max(timestamp) from metrics;'
```

Check network metrics are being populated:

```bash
sqlite3 /tmp/collector-metrics.db 'select max(network_rx_bytes), max(network_tx_bytes) from metrics;'
```
