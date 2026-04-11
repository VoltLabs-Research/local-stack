export const TEAM_CLUSTER_STATUS = {
    WaitingForConnection: 'waiting-for-connection',
    HealthcheckReceived: 'healthcheck-received',
    PreparingEnvironment: 'preparing-environment',
    Connected: 'connected',
    Disconnected: 'disconnected',
    DependenciesInstallationFailed: 'dependency-installation-failed',
    OperatingSystemNotSupported: 'operating-system-not-supported',
    DeleteFailed: 'delete-failed',
    UpdateFailed: 'update-failed'
} as const;

export type TeamClusterStatus = typeof TEAM_CLUSTER_STATUS[keyof typeof TEAM_CLUSTER_STATUS];

export const FAILURE_TEAM_CLUSTER_STATUSES = new Set<TeamClusterStatus>([
    TEAM_CLUSTER_STATUS.DependenciesInstallationFailed,
    TEAM_CLUSTER_STATUS.OperatingSystemNotSupported,
    TEAM_CLUSTER_STATUS.DeleteFailed,
    TEAM_CLUSTER_STATUS.UpdateFailed
]);

export const TEAM_CLUSTER_ROLE = {
    Cluster: 'cluster',
    StorageServer: 'storage-server',
    ComputeNode: 'compute-node'
} as const;

export type TeamClusterRole = typeof TEAM_CLUSTER_ROLE[keyof typeof TEAM_CLUSTER_ROLE];

export interface ParsedCliArgs {
    command: string;
    options: Record<string, string>;
}

export interface DevUserConfig {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
}

export interface TeamConfig {
    name: string;
    description: string;
}

export interface ClusterPorts {
    minio: number;
    redis: number;
    mongodb: number;
    daemon: number;
}

export interface JupyterHostPortRange {
    start: number;
    end: number;
}

export interface ClusterConfig {
    key: 'storage' | 'compute';
    servicePrefix: string;
    role: TeamClusterRole;
    name: string;
    installRoot: string;
    ports: ClusterPorts;
    jupyterHostPortRange: JupyterHostPortRange;
}

export interface BootstrapConfig {
    apiUrl: string;
    internalApiUrl: string;
    webUrl: string;
    daemonNodeEnv: 'development' | 'production';
    outputDirectory: string;
    timeoutMs: number;
    pollIntervalMs: number;
    devUser: DevUserConfig;
    team: TeamConfig;
    clusters: ClusterConfig[];
}

export interface UserSession {
    token: string;
    user: unknown;
}

export interface TeamRecord {
    _id: string;
    name: string;
}

export interface TeamClusterRoleConfig {
    desiredRole?: TeamClusterRole;
}

export interface TeamClusterRecord {
    _id: string;
    name: string;
    status: TeamClusterStatus;
    roleConfig?: TeamClusterRoleConfig;
}

export interface ClusterServiceCredentials {
    username: string;
    password: string;
}

export interface RevealedClusterServices {
    minio: ClusterServiceCredentials;
    mongodb: ClusterServiceCredentials;
    redis: ClusterServiceCredentials;
    daemon: {
        password: string;
    };
}

export interface CreatedClusterRecord {
    teamCluster: TeamClusterRecord;
    enrollmentToken: string | null;
}

export interface ProvisionedClusterRecord {
    clusterConfig: ClusterConfig;
    cluster: TeamClusterRecord;
    services: RevealedClusterServices;
    enrollmentToken: string | null;
}

export interface ProvisionedState {
    token: string;
    user: unknown;
    team: TeamRecord;
    clusters: ProvisionedClusterRecord[];
}

export interface TrackedClusterRecord {
    clusterConfig: ClusterConfig;
    cluster: TeamClusterRecord;
}

export interface TrackedState {
    token: string;
    user: unknown;
    team: TeamRecord;
    clusters: TrackedClusterRecord[];
}

export interface BootstrapStateFile {
    generatedAt: string;
    user: {
        email: string;
    };
    team: {
        id: string;
        name: string;
    };
    clusters: Array<{
        key: ClusterConfig['key'];
        role: TeamClusterRole;
        id: string;
        name: string;
        status: TeamClusterStatus;
        envDirectory: ClusterConfig['key'];
    }>;
    urls: {
        api: string;
        web: string;
        internalApi: string;
    };
}
