#!/usr/bin/env bash

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "${SCRIPT_SOURCE}" && -e "${SCRIPT_SOURCE}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
fi

has_local_stack_layout() {
    [[ -n "${SCRIPT_DIR}" ]] \
        && [[ -f "${SCRIPT_DIR}/stack.sh" ]] \
        && [[ -f "${SCRIPT_DIR}/compose.base.yml" ]]
}

CALLER_ROOT="$(pwd -P)"
DEFAULT_WORKSPACE_DIR="${CALLER_ROOT}/volt-dev"
if has_local_stack_layout; then
    DEFAULT_WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
fi

WORKSPACE_DIR_INPUT="${VOLT_DEV_WORKSPACE_DIR:-${DEFAULT_WORKSPACE_DIR}}"
LOCAL_STACK_REPO_URL="${LOCAL_STACK_REPO_URL:-https://github.com/VoltLabs-Research/local-stack.git}"
LOCAL_STACK_DIR_INPUT="${LOCAL_STACK_CLONE_DIR:-${WORKSPACE_DIR_INPUT}/local-stack}"

if [[ "${WORKSPACE_DIR_INPUT}" = /* ]]; then
    WORKSPACE_DIR="${WORKSPACE_DIR_INPUT}"
else
    WORKSPACE_DIR="${CALLER_ROOT}/${WORKSPACE_DIR_INPUT}"
fi

if [[ "${LOCAL_STACK_DIR_INPUT}" = /* ]]; then
    LOCAL_STACK_DIR="${LOCAL_STACK_DIR_INPUT}"
else
    LOCAL_STACK_DIR="${CALLER_ROOT}/${LOCAL_STACK_DIR_INPUT}"
fi

VOLT_REPO_URL="${VOLT_GIT_URL:-https://github.com/voltlabs-research/Volt.git}"
CLUSTER_DAEMON_REPO_URL="${CLUSTER_DAEMON_GIT_URL:-https://github.com/voltlabs-research/ClusterDaemon.git}"

VOLT_REPO_DIR="${WORKSPACE_DIR}/Volt"
CLUSTER_DAEMON_REPO_DIR="${WORKSPACE_DIR}/ClusterDaemon"

clone_repo() {
    local repo_name="$1"
    local repo_url="$2"
    local target_dir="$3"
    local ref="${4:-}"

    if [[ -d "${target_dir}/.git" ]]; then
        echo "${repo_name} already exists at ${target_dir}"
    elif [[ -e "${target_dir}" ]]; then
        echo "Refusing to clone ${repo_name}: ${target_dir} exists but is not a git checkout" >&2
        exit 1
    else
        echo "Cloning ${repo_name} into ${target_dir}"
        git clone "${repo_url}" "${target_dir}"
    fi

    if [[ -n "${ref}" ]]; then
        echo "Checking out ${repo_name} ref ${ref}"
        git -C "${target_dir}" fetch --all --tags --prune
        git -C "${target_dir}" checkout "${ref}"
    fi
}

command -v git >/dev/null 2>&1 || {
    echo "git is required" >&2
    exit 1
}

if ! has_local_stack_layout; then
    mkdir -p "${WORKSPACE_DIR}"
    clone_repo "local-stack" "${LOCAL_STACK_REPO_URL}" "${LOCAL_STACK_DIR}"
    cd "${WORKSPACE_DIR}"
    exec "${LOCAL_STACK_DIR}/bootstrap-workspace.sh" "$@"
fi

mkdir -p "${WORKSPACE_DIR}"

clone_repo "Volt" "${VOLT_REPO_URL}" "${VOLT_REPO_DIR}" "${VOLT_GIT_REF:-}"
clone_repo "ClusterDaemon" "${CLUSTER_DAEMON_REPO_URL}" "${CLUSTER_DAEMON_REPO_DIR}" "${CLUSTER_DAEMON_GIT_REF:-}"

echo
echo "Workspace ready at ${WORKSPACE_DIR}"
echo "Volt: ${VOLT_REPO_DIR}"
echo "ClusterDaemon: ${CLUSTER_DAEMON_REPO_DIR}"
echo
echo "Next step:"
echo "  cd ${WORKSPACE_DIR}"
echo "  ./local-stack/stack.sh up"
