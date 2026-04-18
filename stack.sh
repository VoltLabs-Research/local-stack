#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="${SCRIPT_DIR}"
CALLER_ROOT="$(pwd -P)"
DEFAULT_WORKSPACE_DIR="${CALLER_ROOT}"
if [[ -d "${SCRIPT_DIR}/../Volt" && -d "${SCRIPT_DIR}/../ClusterDaemon" ]]; then
    DEFAULT_WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
fi

WORKSPACE_DIR_INPUT="${VOLT_DEV_WORKSPACE_DIR:-${DEFAULT_WORKSPACE_DIR}}"

if [[ "${WORKSPACE_DIR_INPUT}" = /* ]]; then
    WORKSPACE_DIR="${WORKSPACE_DIR_INPUT}"
else
    WORKSPACE_DIR="${CALLER_ROOT}/${WORKSPACE_DIR_INPUT}"
fi

VOLT_ROOT="${WORKSPACE_DIR}/Volt"
VOLT_SERVER_ROOT="${VOLT_ROOT}/server"
VOLT_CLIENT_ROOT="${VOLT_ROOT}/client"
GENERATED_DIR="${STACK_ROOT}/.generated"
CLUSTERS_GENERATED_DIR="${GENERATED_DIR}/clusters"
STORAGE_CLUSTER_GENERATED_DIR="${CLUSTERS_GENERATED_DIR}/storage"
COMPUTE_CLUSTER_GENERATED_DIR="${CLUSTERS_GENERATED_DIR}/compute"
BASE_COMPOSE_FILE="${STACK_ROOT}/compose.base.yml"
CLUSTER_COMPOSE_FILE="${STACK_ROOT}/compose.cluster.base.yml"
CLUSTER_REMOTE_COMPOSE_FILE="${STACK_ROOT}/compose.cluster.remote.yml"
CLUSTER_SOURCE_COMPOSE_FILE="${STACK_ROOT}/compose.cluster.source.yml"
CLUSTER_COMPOSE_MODE_FILE="${CLUSTER_REMOTE_COMPOSE_FILE}"

export VOLT_DEV_VOLT_SERVER_DIR="${VOLT_SERVER_ROOT}"
export VOLT_DEV_VOLT_CLIENT_DIR="${VOLT_CLIENT_ROOT}"

PROJECT_NAME="${VOLT_DEV_STACK_PROJECT_NAME:-volt-dev}"
PUBLIC_API_URL="${VOLT_DEV_PUBLIC_API_URL:-http://localhost:8000}"
PUBLIC_WEB_URL="${VOLT_DEV_PUBLIC_WEB_URL:-http://localhost:5173}"
INTERNAL_API_URL="${VOLT_DEV_INTERNAL_API_URL:-http://volt-server:8000}"
MINIO_HOST_PORT="${VOLT_DEV_MINIO_PORT:-9000}"
MINIO_CONSOLE_HOST_PORT="${VOLT_DEV_MINIO_CONSOLE_PORT:-9001}"
PUBLIC_MINIO_URL="${VOLT_DEV_PUBLIC_MINIO_URL:-http://localhost:${MINIO_HOST_PORT}}"
DEFAULT_CLUSTER_DAEMON_IMAGE="ghcr.io/voltlabs-research/volt-cluster-daemon:main"
CLUSTER_DAEMON_IMAGE="${VOLT_DEV_CLUSTER_DAEMON_IMAGE:-${DEFAULT_CLUSTER_DAEMON_IMAGE}}"

export VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}"
export VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}"
export VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}"
export VOLT_DEV_PUBLIC_MINIO_URL="${PUBLIC_MINIO_URL}"
export VOLT_DEV_CLUSTER_DAEMON_IMAGE="${CLUSTER_DAEMON_IMAGE}"

if [[ -n "${VOLT_DEV_CLUSTER_DAEMON_PATH:-}" ]]; then
    CLUSTER_DAEMON_PATH_INPUT="${VOLT_DEV_CLUSTER_DAEMON_PATH}"
elif [[ -d "${WORKSPACE_DIR}/ClusterDaemon" ]]; then
    CLUSTER_DAEMON_PATH_INPUT="${WORKSPACE_DIR}/ClusterDaemon"
else
    CLUSTER_DAEMON_PATH_INPUT=""
fi

BOOTSTRAP_SCRIPT="${STACK_ROOT}/scripts/bootstrap-dev-stack.ts"
BOOTSTRAP_WORKSPACE_SCRIPT="${STACK_ROOT}/bootstrap-workspace.sh"

ensure_tools() {
    command -v docker >/dev/null 2>&1 || {
        echo "docker is required" >&2
        exit 1
    }

    docker compose version >/dev/null 2>&1 || {
        echo "docker compose is required" >&2
        exit 1
    }

    command -v node >/dev/null 2>&1 || {
        echo "node is required" >&2
        exit 1
    }

    [[ -f "${BOOTSTRAP_SCRIPT}" ]] || {
        echo "Expected ${BOOTSTRAP_SCRIPT}" >&2
        exit 1
    }

    [[ -f "${VOLT_SERVER_ROOT}/Dockerfile.dev" ]] || {
        echo "Expected ${VOLT_SERVER_ROOT}/Dockerfile.dev. Run ${BOOTSTRAP_WORKSPACE_SCRIPT} in the workspace root, or set VOLT_DEV_WORKSPACE_DIR." >&2
        exit 1
    }

    [[ -f "${VOLT_CLIENT_ROOT}/Dockerfile.dev" ]] || {
        echo "Expected ${VOLT_CLIENT_ROOT}/Dockerfile.dev. Run ${BOOTSTRAP_WORKSPACE_SCRIPT} in the workspace root, or set VOLT_DEV_WORKSPACE_DIR." >&2
        exit 1
    }
}

resolve_cluster_daemon_path() {
    local input_path="$1"

    if [[ "${input_path}" = /* ]]; then
        [[ -d "${input_path}" ]] || {
            echo "ClusterDaemon path '${input_path}' does not exist" >&2
            exit 1
        }
        (
            cd "${input_path}"
            pwd -P
        )
        return 0
    fi

    if [[ -d "${input_path}" ]]; then
        (
            cd "${input_path}"
            pwd -P
        )
        return 0
    fi

    if [[ -d "${STACK_ROOT}/${input_path}" ]]; then
        (
            cd "${STACK_ROOT}/${input_path}"
            pwd -P
        )
        return 0
    fi

    echo "ClusterDaemon path '${input_path}' does not exist relative to the current directory or the local-stack root" >&2
    exit 1
}

assert_cluster_daemon_source_layout() {
    local cluster_daemon_path="$1"

    [[ -f "${cluster_daemon_path}/Dockerfile.dev" ]] || {
        echo "Expected ${cluster_daemon_path}/Dockerfile.dev" >&2
        exit 1
    }

    [[ -f "${cluster_daemon_path}/package.json" ]] || {
        echo "Expected ${cluster_daemon_path}/package.json" >&2
        exit 1
    }
}

ensure_generated_layout() {
    mkdir -p "${GENERATED_DIR}"
    ensure_cluster_generated_layout "${STORAGE_CLUSTER_GENERATED_DIR}"
    ensure_cluster_generated_layout "${COMPUTE_CLUSTER_GENERATED_DIR}"
}

ensure_cluster_generated_layout() {
    local cluster_dir="$1"

    mkdir -p "${cluster_dir}"

    [[ -f "${cluster_dir}/minio.env" ]] || : > "${cluster_dir}/minio.env"
    [[ -f "${cluster_dir}/mongodb.env" ]] || : > "${cluster_dir}/mongodb.env"
    [[ -f "${cluster_dir}/redis.env" ]] || cat > "${cluster_dir}/redis.env" <<'EOF'
REDIS_USERNAME=placeholder
REDIS_PASSWORD=placeholder
EOF
    [[ -f "${cluster_dir}/redis.acl" ]] || cat > "${cluster_dir}/redis.acl" <<'EOF'
user default off
user placeholder on >placeholder ~* &* +@all
EOF
    [[ -f "${cluster_dir}/daemon.env" ]] || : > "${cluster_dir}/daemon.env"
}

configure_cluster_daemon_compose() {
    CLUSTER_COMPOSE_MODE_FILE="${CLUSTER_REMOTE_COMPOSE_FILE}"

    if [[ -z "${CLUSTER_DAEMON_PATH_INPUT}" ]]; then
        unset VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR || true
        return
    fi

    local cluster_daemon_source_path
    cluster_daemon_source_path="$(resolve_cluster_daemon_path "${CLUSTER_DAEMON_PATH_INPUT}")"
    assert_cluster_daemon_source_layout "${cluster_daemon_source_path}"
    export VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR="${cluster_daemon_source_path}"
    CLUSTER_COMPOSE_MODE_FILE="${CLUSTER_SOURCE_COMPOSE_FILE}"
}

docker_compose_base() {
    docker compose --project-directory "${STACK_ROOT}" -p "${PROJECT_NAME}" -f "${BASE_COMPOSE_FILE}" "$@"
}

docker_compose_all() {
    docker compose --project-directory "${STACK_ROOT}" -p "${PROJECT_NAME}" -f "${BASE_COMPOSE_FILE}" -f "${CLUSTER_COMPOSE_FILE}" -f "${CLUSTER_COMPOSE_MODE_FILE}" "$@"
}

cleanup_managed_runtime_containers() {
    local managed_container_ids
    managed_container_ids="$(docker ps -aq --filter label=volt.managed=true)"

    if [[ -z "${managed_container_ids}" ]]; then
        return 0
    fi

    docker rm -f ${managed_container_ids} >/dev/null
}

base_up_services() {
    local services=(
        volt-mongodb
        volt-redis
        volt-minio
        volt-server
        volt-client
    )

    printf '%s\n' "${services[@]}"
}

cluster_up_services() {
    local services=(
        storage-mongodb
        storage-redis
        storage-minio
        storage-daemon
        compute-mongodb
        compute-redis
        compute-minio
        compute-daemon
    )

    printf '%s\n' "${services[@]}"
}

run_bootstrap_provision() {
    VOLT_DEV_STACK_PROJECT_NAME="${PROJECT_NAME}" \
    VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}" \
    VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}" \
    VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}" \
    node "${BOOTSTRAP_SCRIPT}" \
        provision \
        --output-dir "${CLUSTERS_GENERATED_DIR}"
}

run_bootstrap_wait_cluster() {
    VOLT_DEV_STACK_PROJECT_NAME="${PROJECT_NAME}" \
    VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}" \
    VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}" \
    VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}" \
    node "${BOOTSTRAP_SCRIPT}" \
        wait-cluster \
        --output-dir "${CLUSTERS_GENERATED_DIR}"
}

pull_remote_cluster_daemon_images() {
    if [[ -n "${CLUSTER_DAEMON_PATH_INPUT}" ]]; then
        return 0
    fi

    docker_compose_all pull storage-daemon compute-daemon
}

prepare_stack_state() {
    ensure_generated_layout
    configure_cluster_daemon_compose
}

cmd_up() {
    prepare_stack_state
    cleanup_managed_runtime_containers

    mapfile -t base_services < <(base_up_services)
    docker_compose_base up -d --build --remove-orphans "${base_services[@]}"

    run_bootstrap_provision
    pull_remote_cluster_daemon_images

    mapfile -t cluster_services < <(cluster_up_services)
    docker_compose_all up -d --build --remove-orphans "${cluster_services[@]}"

    run_bootstrap_wait_cluster
}

cmd_down() {
    prepare_stack_state
    cleanup_managed_runtime_containers
    docker_compose_all down --remove-orphans
}

cmd_reset() {
    prepare_stack_state
    cleanup_managed_runtime_containers
    docker_compose_all down --volumes --remove-orphans
    rm -rf "${GENERATED_DIR}"
}

cmd_bootstrap() {
    prepare_stack_state
    run_bootstrap_provision
}

cmd_logs() {
    prepare_stack_state
    shift || true
    docker_compose_all logs -f "$@"
}

cmd_ps() {
    prepare_stack_state
    docker_compose_all ps
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  up         Build and start Volt, bootstrap dev data, then start the cluster daemon stack
  down       Stop the stack without removing volumes
  reset      Stop the stack, remove volumes, and delete generated env files
  bootstrap  Re-run the API bootstrap and rewrite cluster env files
  logs       Tail compose logs
  ps         Show compose service status

Environment overrides:
  VOLT_DEV_PUBLIC_API_URL      Default: http://localhost:8000
  VOLT_DEV_PUBLIC_WEB_URL      Default: http://localhost:5173
  VOLT_DEV_PUBLIC_MINIO_URL    Default: ${PUBLIC_MINIO_URL}
  VOLT_DEV_INTERNAL_API_URL    Default: http://volt-server:8000
  VOLT_DEV_MINIO_PORT          Default: ${MINIO_HOST_PORT}
  VOLT_DEV_MINIO_CONSOLE_PORT  Default: ${MINIO_CONSOLE_HOST_PORT}
  VOLT_DEV_WORKSPACE_DIR       Optional directory containing Volt/ and ClusterDaemon/. Default: <current-dir>
  VOLT_DEV_CLUSTER_DAEMON_PATH Optional path to a local ClusterDaemon checkout
  VOLT_DEV_CLUSTER_DAEMON_IMAGE Default: ${CLUSTER_DAEMON_IMAGE}
  VOLT_DEV_STACK_PROJECT_NAME
  VOLT_DEV_USER_EMAIL
  VOLT_DEV_USER_PASSWORD
  VOLT_DEV_TEAM_NAME
  VOLT_DEV_CLUSTER_NAME
  VOLT_DEV_STORAGE_CLUSTER_NAME
  VOLT_DEV_COMPUTE_CLUSTER_NAME
EOF
}

main() {
    ensure_tools

    local command="${1:-}"
    case "${command}" in
        up)
            cmd_up
            ;;
        down)
            cmd_down
            ;;
        reset)
            cmd_reset
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        logs)
            cmd_logs "$@"
            ;;
        ps)
            cmd_ps
            ;;
        *)
            usage
            [[ -n "${command}" ]] && exit 1
            ;;
    esac
}

main "$@"
