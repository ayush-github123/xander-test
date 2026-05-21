#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CLUSTER="${KIND_CLUSTER:-kind}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
KIND_VERSION="${KIND_VERSION:-v0.27.0}"
SCENARIO_DIR="${SCENARIO_DIR:-telemetry-collector/scenarios/1-log-heavy-noisy-neighbor}"
SCENARIO_NAMESPACE="${SCENARIO_NAMESPACE:-default}"
SCENARIO_PODS="${SCENARIO_PODS:-pod-x-noisy pod-y-db}"

log() {
  printf '\n==> %s\n' "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_system_deps() {
  local missing=()
  for cmd in "$PYTHON_BIN" pip go docker kubectl kind sqlite3; do
    if ! has_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return
  fi

  log "Missing commands: ${missing[*]}"
  if has_cmd pacman; then
    sudo pacman -S --needed python python-pip go docker kubectl kind sqlite
  elif has_cmd apt-get; then
    local apt_packages=()
    for cmd in "${missing[@]}"; do
      case "$cmd" in
        "$PYTHON_BIN") apt_packages+=(python3) ;;
        pip) apt_packages+=(python3-pip python3-venv) ;;
        go) apt_packages+=(golang-go) ;;
        docker) apt_packages+=(docker.io) ;;
        sqlite3) apt_packages+=(sqlite3) ;;
      esac
    done

    if [ "${#apt_packages[@]}" -gt 0 ]; then
      sudo apt-get update
      sudo apt-get install -y "${apt_packages[@]}"
    fi

    if ! has_cmd kubectl; then
      echo "kubectl is not available from this apt setup. Install it from https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
      exit 1
    fi

    if ! has_cmd kind; then
      if ! has_cmd go; then
        echo "kind is not available from this apt setup, and Go is not installed. Install kind from https://kind.sigs.k8s.io/docs/user/quick-start/"
        exit 1
      fi
      log "Installing kind ${KIND_VERSION}"
      go install "sigs.k8s.io/kind@${KIND_VERSION}"
      local go_bin_dir
      go_bin_dir="$(go env GOPATH)/bin"
      export PATH="$go_bin_dir:$PATH"
      if ! has_cmd kind && [ -x "$go_bin_dir/kind" ]; then
        sudo install -m 0755 "$go_bin_dir/kind" /usr/local/bin/kind
      fi
      if ! has_cmd kind; then
        echo "Installed kind, but it is not on PATH. Add $go_bin_dir to PATH and rerun this script."
        exit 1
      fi
    fi
  else
    echo "Install these first: Python 3, pip, Go, Docker, kubectl, kind, sqlite3"
    exit 1
  fi
}

ensure_docker_running() {
  if docker info >/dev/null 2>&1; then
    return
  fi

  log "Starting Docker"
  if has_cmd systemctl; then
    sudo systemctl start docker
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not reachable. Start Docker and rerun this script."
    exit 1
  fi
}

setup_python_env() {
  log "Setting up Python environment"
  cd "$ROOT_DIR"
  "$PYTHON_BIN" -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  python -m pip install --upgrade pip
  pip install streamlit pandas numpy altair requests
  if [ -f agent/requirements.txt ]; then
    pip install -r agent/requirements.txt
  fi
}

download_go_modules() {
  log "Downloading Go modules"
  for dir in telemetry-collector telemetry-api aggregation-engine context-engine; do
    if [ -f "$ROOT_DIR/$dir/go.mod" ]; then
      (cd "$ROOT_DIR/$dir" && go mod download)
    fi
  done
}

ensure_kind_cluster() {
  log "Checking kind cluster"
  if ! kind get clusters | grep -qx "$KIND_CLUSTER"; then
    kind create cluster --name "$KIND_CLUSTER"
  fi
  kubectl cluster-info >/dev/null
}

deploy_scenario() {
  log "Deploying scenario 1: log-heavy noisy neighbor"
  kubectl create namespace "$SCENARIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create serviceaccount default -n "$SCENARIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$ROOT_DIR/$SCENARIO_DIR"

  log "Waiting for scenario pods"
  for pod in $SCENARIO_PODS; do
    kubectl wait --for=condition=Ready "pod/$pod" -n "$SCENARIO_NAMESPACE" --timeout=180s
  done
}

deploy_collector() {
  log "Building and deploying telemetry collector"
  cd "$ROOT_DIR/telemetry-collector"
  docker build -t telemetry-collector:latest -f Dockerfile .
  kind load docker-image telemetry-collector:latest --name "$KIND_CLUSTER"
  kubectl apply -f k8s/deployment.yaml
  kubectl rollout status daemonset/telemetry-collector -n telemetry-system --timeout=120s
}

main() {
  install_system_deps
  ensure_docker_running
  setup_python_env
  download_go_modules
  ensure_kind_cluster
  deploy_scenario
  deploy_collector

  log "Project is ready"
  cat <<EOF
Run Streamlit with:

  cd "$ROOT_DIR"
  source .venv/bin/activate
  streamlit run streamlit_app.py

In the sidebar, use /tmp/collector-metrics.db and keep Live charts enabled.

Scenario 1 is running in namespace $SCENARIO_NAMESPACE:

  kubectl get pods -n "$SCENARIO_NAMESPACE" pod-x-noisy pod-y-db

The telemetry collector runs on the node and will collect telemetry from that node, including these scenario pods.
EOF
}

main "$@"
