## Quick Start

Run the bootstrap script directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/VoltLabs-Research/local-stack/main/bootstrap-workspace.sh | bash
cd ./volt-dev
./local-stack/stack.sh up
```

The bootstrap script will create this layout:

```text
<current-directory>/
  volt-dev/
    local-stack/
      bootstrap-workspace.sh
      stack.sh
    Volt/
    ClusterDaemon/
```

## Manual Usage

If `local-stack` is already checked out:

```bash
cd ./volt-dev
./local-stack/bootstrap-workspace.sh

./local-stack/stack.sh down
./local-stack/stack.sh reset
./local-stack/stack.sh ps
```

## Environment Variables

```bash
export LOCAL_STACK_REPO_URL="https://github.com/VoltLabs-Research/local-stack.git"
export LOCAL_STACK_CLONE_DIR="/path/to/volt-dev/local-stack"
export VOLT_GIT_URL="https://github.com/voltlabs-research/Volt.git"
export CLUSTER_DAEMON_GIT_URL="https://github.com/voltlabs-research/ClusterDaemon.git"
export VOLT_GIT_REF="main"
export CLUSTER_DAEMON_GIT_REF="main"
export VOLT_DEV_WORKSPACE_DIR="/path/to/volt-dev"
```

`VOLT_DEV_WORKSPACE_DIR` should point to the workspace directory that contains `local-stack/`, `Volt/`, and `ClusterDaemon/`.

If you want to use a different local `ClusterDaemon` checkout for the daemon services:

```bash
export VOLT_DEV_CLUSTER_DAEMON_PATH="/path/to/ClusterDaemon"
cd /path/to/volt-dev
./local-stack/stack.sh up
```

## Defaults

If `VOLT_DEV_WORKSPACE_DIR` is not set:

1. `bootstrap-workspace.sh` creates and uses `./volt-dev`.
2. `stack.sh` uses the parent directory of its `local-stack/` checkout when that layout exists.
