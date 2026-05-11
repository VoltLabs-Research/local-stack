#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="${SCRIPT_DIR}"

if [[ -f "${STACK_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${STACK_ROOT}/.env"
    set +a
fi

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
COMPOSE_FILE="${STACK_ROOT}/compose.yml"
BOOTSTRAP_CONTAINER_ROOT="/tmp/volt-local-stack"
BOOTSTRAP_CONTAINER_OUTPUT_DIR="${BOOTSTRAP_CONTAINER_ROOT}/.generated/clusters"

export VOLT_DEV_VOLT_SERVER_DIR="${VOLT_SERVER_ROOT}"
export VOLT_DEV_VOLT_CLIENT_DIR="${VOLT_CLIENT_ROOT}"
export VOLT_DEV_VOLT_SERVER_BIND_DIR="${VOLT_DEV_VOLT_SERVER_HOST_DIR:-${VOLT_SERVER_ROOT}}"
export VOLT_DEV_VOLT_CLIENT_BIND_DIR="${VOLT_DEV_VOLT_CLIENT_HOST_DIR:-${VOLT_CLIENT_ROOT}}"
export VOLT_DEV_VOLT_SERVER_MOUNT_SOURCE="${VOLT_DEV_VOLT_SERVER_BIND_DIR}"
export VOLT_DEV_VOLT_CLIENT_MOUNT_SOURCE="${VOLT_DEV_VOLT_CLIENT_BIND_DIR}"

PROJECT_NAME="${VOLT_DEV_STACK_PROJECT_NAME:-volt-dev}"
PUBLIC_HOST_DEFAULT="${VOLT_DEV_PUBLIC_HOST:-localhost}"
API_HOST_PORT="${VOLT_DEV_API_PORT:-8100}"
WEB_HOST_PORT="${VOLT_DEV_WEB_PORT:-5273}"
PUBLIC_API_URL="${VOLT_DEV_PUBLIC_API_URL:-http://${PUBLIC_HOST_DEFAULT}:${API_HOST_PORT}}"
PUBLIC_WEB_URL="${VOLT_DEV_PUBLIC_WEB_URL:-http://${PUBLIC_HOST_DEFAULT}:${WEB_HOST_PORT}}"
INTERNAL_API_URL="${VOLT_DEV_INTERNAL_API_URL:-http://volt-server:8000}"
BOOTSTRAP_API_URL="${VOLT_DEV_BOOTSTRAP_API_URL:-${PUBLIC_API_URL}}"
MINIO_HOST_PORT="${VOLT_DEV_MINIO_PORT:-9100}"
MINIO_CONSOLE_HOST_PORT="${VOLT_DEV_MINIO_CONSOLE_PORT:-9101}"
PUBLIC_MINIO_URL="${VOLT_DEV_PUBLIC_MINIO_URL:-http://${PUBLIC_HOST_DEFAULT}:${MINIO_HOST_PORT}}"
DEFAULT_CLUSTER_DAEMON_IMAGE="ghcr.io/voltlabs-research/volt-cluster-daemon:main"
CLUSTER_DAEMON_IMAGE="${VOLT_DEV_CLUSTER_DAEMON_IMAGE:-${DEFAULT_CLUSTER_DAEMON_IMAGE}}"
DOWN_TIMEOUT_SECONDS="${VOLT_DEV_DOWN_TIMEOUT_SECONDS:-15}"

resolve_url_host() {
    local url="$1"
    local without_scheme="${url#*://}"
    local authority="${without_scheme%%/*}"

    if [[ "${authority}" == \[*\]* ]]; then
        local bracket_host="${authority%%]*}"
        printf '%s]\n' "${bracket_host}"
        return
    fi

    printf '%s\n' "${authority%%:*}"
}

PUBLIC_API_HOST="${VOLT_DEV_PUBLIC_HOST:-$(resolve_url_host "${PUBLIC_API_URL}")}"

export VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}"
export VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}"
export VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}"
export VOLT_DEV_BOOTSTRAP_API_URL="${BOOTSTRAP_API_URL}"
export VOLT_DEV_PUBLIC_MINIO_URL="${PUBLIC_MINIO_URL}"
export VOLT_DEV_PUBLIC_HOST="${PUBLIC_API_HOST}"
export VOLT_DEV_CLUSTER_DAEMON_IMAGE="${CLUSTER_DAEMON_IMAGE}"
export VOLT_DEV_API_PORT="${API_HOST_PORT}"
export VOLT_DEV_WEB_PORT="${WEB_HOST_PORT}"
export VOLT_DEV_MINIO_PORT="${MINIO_HOST_PORT}"
export VOLT_DEV_MINIO_CONSOLE_PORT="${MINIO_CONSOLE_HOST_PORT}"

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

    [[ -f "${COMPOSE_FILE}" ]] || {
        echo "Expected ${COMPOSE_FILE}" >&2
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
    if [[ -z "${CLUSTER_DAEMON_PATH_INPUT}" ]]; then
        unset VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR || true
        unset VOLT_DEV_CLUSTER_DAEMON_BIND_DIR || true
        return
    fi

    local cluster_daemon_source_path
    cluster_daemon_source_path="$(resolve_cluster_daemon_path "${CLUSTER_DAEMON_PATH_INPUT}")"
    assert_cluster_daemon_source_layout "${cluster_daemon_source_path}"
    export VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR="${cluster_daemon_source_path}"
    export VOLT_DEV_CLUSTER_DAEMON_BIND_DIR="${VOLT_DEV_CLUSTER_DAEMON_HOST_DIR:-${cluster_daemon_source_path}}"
}

configure_mount_sources() {
    if source_mounts_enabled; then
        export VOLT_DEV_VOLT_SERVER_MOUNT_SOURCE="${VOLT_DEV_VOLT_SERVER_BIND_DIR}"
        export VOLT_DEV_VOLT_CLIENT_MOUNT_SOURCE="${VOLT_DEV_VOLT_CLIENT_BIND_DIR}"
    else
        export VOLT_DEV_VOLT_SERVER_MOUNT_SOURCE="volt-server-app-src"
        export VOLT_DEV_VOLT_CLIENT_MOUNT_SOURCE="volt-client-app-src"
    fi

    if source_mounts_enabled && [[ -n "${VOLT_DEV_CLUSTER_DAEMON_BIND_DIR:-}" ]]; then
        export VOLT_DEV_CLUSTER_DAEMON_MOUNT_SOURCE="${VOLT_DEV_CLUSTER_DAEMON_BIND_DIR}"
    else
        export VOLT_DEV_CLUSTER_DAEMON_MOUNT_SOURCE="cluster-daemon-app-src"
    fi
}

build_local_cluster_daemon_image() {
    if [[ -z "${VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR:-}" ]]; then
        return 0
    fi

    docker build \
        -f "${VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR}/Dockerfile.dev" \
        -t "${CLUSTER_DAEMON_IMAGE}" \
        "${VOLT_DEV_CLUSTER_DAEMON_SOURCE_DIR}"
}

docker_compose_base() {
    docker compose --project-directory "${STACK_ROOT}" -p "${PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

docker_compose_all() {
    docker_compose_base "$@"
}

source_mounts_enabled() {
    case "${VOLT_DEV_NO_SOURCE_MOUNTS:-false}" in
        1|true|TRUE|yes|YES)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

bootstrap_in_container_enabled() {
    case "${VOLT_DEV_BOOTSTRAP_IN_CONTAINER:-}" in
        1|true|TRUE|yes|YES)
            return 0
            ;;
        0|false|FALSE|no|NO)
            return 1
            ;;
    esac

    if source_mounts_enabled; then
        return 1
    fi

    return 0
}

server_container_id() {
    docker_compose_base ps -q volt-server
}

force_stop_server_container() {
    local container_id

    container_id="$(server_container_id)"
    if [[ -z "${container_id}" ]]; then
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout "${DOWN_TIMEOUT_SECONDS}s" docker kill "${container_id}" >/dev/null 2>&1 || true
        return 0
    fi

    docker kill "${container_id}" >/dev/null 2>&1 || true
}

copy_bootstrap_scripts_to_server() {
    local container_id

    container_id="$(server_container_id)"
    [[ -n "${container_id}" ]] || {
        echo "volt-server container is not running; cannot run container bootstrap" >&2
        exit 1
    }

    docker exec "${container_id}" rm -rf "${BOOTSTRAP_CONTAINER_ROOT}"
    docker exec "${container_id}" mkdir -p "${BOOTSTRAP_CONTAINER_ROOT}"
    docker cp "${STACK_ROOT}/scripts" "${container_id}:${BOOTSTRAP_CONTAINER_ROOT}/scripts"
}

run_bootstrap_in_server_container() {
    local command="$1"
    local container_id

    copy_bootstrap_scripts_to_server
    container_id="$(server_container_id)"

    docker exec \
        -w /app \
        -e VOLT_DEV_STACK_PROJECT_NAME="${PROJECT_NAME}" \
        -e VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}" \
        -e VOLT_DEV_BOOTSTRAP_API_URL="http://127.0.0.1:8000" \
        -e VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}" \
        -e VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}" \
        "${container_id}" \
        node "${BOOTSTRAP_CONTAINER_ROOT}/scripts/bootstrap-dev-stack.ts" \
        "${command}" \
        --output-dir "${BOOTSTRAP_CONTAINER_OUTPUT_DIR}"
}

copy_bootstrap_generated_from_server() {
    local container_id

    container_id="$(server_container_id)"
    [[ -n "${container_id}" ]] || {
        echo "volt-server container is not running; cannot copy bootstrap artifacts" >&2
        exit 1
    }

    rm -rf "${CLUSTERS_GENERATED_DIR}"
    mkdir -p "${CLUSTERS_GENERATED_DIR}"
    docker cp "${container_id}:${BOOTSTRAP_CONTAINER_OUTPUT_DIR}/." "${CLUSTERS_GENERATED_DIR}/"
}

read_generated_team_cluster_ids() {
    local env_file
    local line
    local team_cluster_id

    if [[ ! -d "${CLUSTERS_GENERATED_DIR}" ]]; then
        return 0
    fi

    while IFS= read -r env_file; do
        while IFS= read -r line; do
            case "${line}" in
                TEAM_CLUSTER_ID=*)
                    team_cluster_id="${line#TEAM_CLUSTER_ID=}"
                    if [[ -n "${team_cluster_id}" ]]; then
                        printf '%s\n' "${team_cluster_id}"
                    fi
                    ;;
            esac
        done < "${env_file}"
    done < <(find "${CLUSTERS_GENERATED_DIR}" -mindepth 2 -maxdepth 2 -type f -name daemon.env -print 2>/dev/null)
}

cleanup_managed_runtime_containers() {
    local team_cluster_ids
    local team_cluster_id
    local managed_container_ids

    mapfile -t team_cluster_ids < <(read_generated_team_cluster_ids | sort -u)

    if [[ "${#team_cluster_ids[@]}" -eq 0 ]]; then
        return 0
    fi

    for team_cluster_id in "${team_cluster_ids[@]}"; do
        managed_container_ids="$(docker ps -aq \
            --filter label=volt.managed=true \
            --filter label=volt.team-cluster.id="${team_cluster_id}")"

        if [[ -z "${managed_container_ids}" ]]; then
            continue
        fi

        docker rm -f ${managed_container_ids} >/dev/null
    done
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
    if bootstrap_in_container_enabled; then
        run_bootstrap_in_server_container provision
        copy_bootstrap_generated_from_server
        return
    fi

    VOLT_DEV_STACK_PROJECT_NAME="${PROJECT_NAME}" \
    VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}" \
    VOLT_DEV_BOOTSTRAP_API_URL="${BOOTSTRAP_API_URL}" \
    VOLT_DEV_PUBLIC_WEB_URL="${PUBLIC_WEB_URL}" \
    VOLT_DEV_INTERNAL_API_URL="${INTERNAL_API_URL}" \
    node "${BOOTSTRAP_SCRIPT}" \
        provision \
        --output-dir "${CLUSTERS_GENERATED_DIR}"
}

run_bootstrap_wait_cluster() {
    if bootstrap_in_container_enabled; then
        run_bootstrap_in_server_container wait-cluster
        return
    fi

    VOLT_DEV_STACK_PROJECT_NAME="${PROJECT_NAME}" \
    VOLT_DEV_PUBLIC_API_URL="${PUBLIC_API_URL}" \
    VOLT_DEV_BOOTSTRAP_API_URL="${BOOTSTRAP_API_URL}" \
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

    if docker image inspect "${CLUSTER_DAEMON_IMAGE}" >/dev/null 2>&1; then
        return 0
    fi

    docker_compose_all pull storage-daemon compute-daemon
}

prepare_stack_state() {
    ensure_generated_layout
    configure_cluster_daemon_compose
    configure_mount_sources
}

cmd_up() {
    prepare_stack_state
    cleanup_managed_runtime_containers

    mapfile -t base_services < <(base_up_services)
    docker_compose_base up -d --build "${base_services[@]}"

    run_bootstrap_provision
    build_local_cluster_daemon_image
    pull_remote_cluster_daemon_images

    mapfile -t cluster_services < <(cluster_up_services)
    docker_compose_all up -d --no-build --no-deps --remove-orphans "${cluster_services[@]}"

    run_bootstrap_wait_cluster
}

cmd_down() {
    prepare_stack_state
    cleanup_managed_runtime_containers
    force_stop_server_container
    docker_compose_all down --timeout "${DOWN_TIMEOUT_SECONDS}" --remove-orphans
}

cmd_reset() {
    prepare_stack_state
    cleanup_managed_runtime_containers
    force_stop_server_container
    docker_compose_all down --timeout "${DOWN_TIMEOUT_SECONDS}" --volumes --remove-orphans
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
  VOLT_DEV_BOOTSTRAP_API_URL   API URL used by host-side bootstrap; defaults to VOLT_DEV_PUBLIC_API_URL
  VOLT_DEV_BOOTSTRAP_IN_CONTAINER Run bootstrap inside volt-server; defaults to true when source mounts are disabled
  VOLT_DEV_API_PORT           Default: ${API_HOST_PORT}
  VOLT_DEV_WEB_PORT           Default: ${WEB_HOST_PORT}
  VOLT_DEV_MINIO_PORT          Default: ${MINIO_HOST_PORT}
  VOLT_DEV_MINIO_CONSOLE_PORT  Default: ${MINIO_CONSOLE_HOST_PORT}
  VOLT_DEV_WORKSPACE_DIR       Optional directory containing Volt/ and ClusterDaemon/. Default: <current-dir>
  VOLT_DEV_CLUSTER_DAEMON_PATH Optional path to a local ClusterDaemon checkout
  VOLT_DEV_CLUSTER_DAEMON_IMAGE Default: ${CLUSTER_DAEMON_IMAGE}
  VOLT_DEV_DOWN_TIMEOUT_SECONDS Timeout (seconds) used by down/reset docker compose down. Default: ${DOWN_TIMEOUT_SECONDS}
  VOLT_DEV_NO_SOURCE_MOUNTS   Copy source into images instead of bind-mounting it
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
