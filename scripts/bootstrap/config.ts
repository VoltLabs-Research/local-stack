import path from 'node:path';
import { TEAM_CLUSTER_ROLE, type BootstrapConfig, type ClusterConfig } from './types.ts';

const DEFAULT_TIMEOUT_MS = 180_000;
const DEFAULT_POLL_INTERVAL_MS = 2_500;

const readFirstText = (...values: Array<string | undefined>): string | undefined => {
    for (const value of values) {
        if (typeof value === 'string' && value.trim().length > 0) {
            return value.trim();
        }
    }

    return undefined;
};

const parseFiniteNumber = (value: string | number, context: string): number => {
    const parsedValue = typeof value === 'number' ? value : Number(value);
    if (!Number.isFinite(parsedValue)) {
        throw new Error(`${context} must be a finite number`);
    }

    return parsedValue;
};

const readFirstNumber = (context: string, ...values: Array<string | number | undefined>): number => {
    for (const value of values) {
        if (value === undefined) {
            continue;
        }

        if (typeof value === 'string' && value.trim().length === 0) {
            continue;
        }

        return parseFiniteNumber(value, context);
    }

    throw new Error(`${context} is required`);
};

const resolveClusterName = (
    explicitName: string | undefined,
    fallbackName: string,
    suffix: string,
    legacyClusterName: string | undefined
): string => {
    if (explicitName) {
        return explicitName;
    }

    if (legacyClusterName) {
        return `${legacyClusterName} ${suffix}`;
    }

    return fallbackName;
};

const createClusterConfig = (input: {
    key: ClusterConfig['key'];
    servicePrefix: string;
    role: ClusterConfig['role'];
    name: string;
    installRoot: string;
    ports: ClusterConfig['ports'];
    jupyterHostPortRange: ClusterConfig['jupyterHostPortRange'];
}): ClusterConfig => {
    return {
        key: input.key,
        servicePrefix: input.servicePrefix,
        role: input.role,
        name: input.name,
        installRoot: input.installRoot,
        ports: input.ports,
        jupyterHostPortRange: input.jupyterHostPortRange
    };
};

export const createBootstrapConfig = (input: {
    options: Record<string, string>;
    env: NodeJS.ProcessEnv;
    defaultOutputDirectory: string;
}): BootstrapConfig => {
    const { options, env, defaultOutputDirectory } = input;
    const legacyClusterName = readFirstText(options.clusterName, env.VOLT_DEV_CLUSTER_NAME);
    const daemonNodeEnv =
        readFirstText(options.daemonNodeEnv, env.VOLT_DEV_CLUSTER_DAEMON_NODE_ENV)
        || (env.VOLT_DEV_CLUSTER_DAEMON_PATH ? 'development' : 'production');
    const defaultInstallRoot = readFirstText(
        options.installRoot,
        env.VOLT_DEV_CLUSTER_INSTALL_ROOT
    ) || '/opt/volt-dev/clusters';

    return {
        apiUrl: readFirstText(options.apiUrl, env.VOLT_DEV_PUBLIC_API_URL) || 'http://localhost:8000',
        internalApiUrl: readFirstText(options.internalApiUrl, env.VOLT_DEV_INTERNAL_API_URL) || 'http://volt-server:8000',
        webUrl: readFirstText(options.webUrl, env.VOLT_DEV_PUBLIC_WEB_URL) || 'http://localhost:5173',
        daemonNodeEnv: daemonNodeEnv === 'development' ? 'development' : 'production',
        outputDirectory: path.resolve(
            readFirstText(options.outputDir, env.VOLT_DEV_CLUSTER_OUTPUT_DIR) || defaultOutputDirectory
        ),
        timeoutMs: readFirstNumber(
            'bootstrap timeout',
            options.timeoutMs,
            env.VOLT_DEV_BOOTSTRAP_TIMEOUT_MS,
            DEFAULT_TIMEOUT_MS
        ),
        pollIntervalMs: readFirstNumber(
            'bootstrap poll interval',
            options.pollIntervalMs,
            env.VOLT_DEV_BOOTSTRAP_POLL_INTERVAL_MS,
            DEFAULT_POLL_INTERVAL_MS
        ),
        devUser: {
            email: readFirstText(options.userEmail, env.VOLT_DEV_USER_EMAIL) || 'dev@volt.local',
            password: readFirstText(options.userPassword, env.VOLT_DEV_USER_PASSWORD) || 'DevPassword123!',
            firstName: readFirstText(options.userFirstName, env.VOLT_DEV_USER_FIRST_NAME) || 'Volt',
            lastName: readFirstText(options.userLastName, env.VOLT_DEV_USER_LAST_NAME) || 'Developer'
        },
        team: {
            name: readFirstText(options.teamName, env.VOLT_DEV_TEAM_NAME) || 'Volt Dev Team',
            description: readFirstText(options.teamDescription, env.VOLT_DEV_TEAM_DESCRIPTION)
                || 'Repo-local Docker development workspace for Volt'
        },
        clusters: [
            createClusterConfig({
                key: 'storage',
                servicePrefix: 'storage',
                role: TEAM_CLUSTER_ROLE.StorageServer,
                name: resolveClusterName(
                    readFirstText(options.storageClusterName, env.VOLT_DEV_STORAGE_CLUSTER_NAME),
                    'Local Dev Storage Server',
                    'Storage Server',
                    legacyClusterName
                ),
                installRoot: readFirstText(options.storageInstallRoot, env.VOLT_DEV_STORAGE_CLUSTER_INSTALL_ROOT)
                    || path.posix.join(defaultInstallRoot, 'storage'),
                ports: {
                    minio: readFirstNumber(
                        'storage cluster MinIO port',
                        options.storageClusterMinioPort,
                        env.VOLT_DEV_STORAGE_CLUSTER_MINIO_PORT,
                        options.clusterMinioPort,
                        env.VOLT_DEV_CLUSTER_MINIO_PORT,
                        9000
                    ),
                    redis: readFirstNumber(
                        'storage cluster Redis port',
                        options.storageClusterRedisPort,
                        env.VOLT_DEV_STORAGE_CLUSTER_REDIS_PORT,
                        options.clusterRedisPort,
                        env.VOLT_DEV_CLUSTER_REDIS_PORT,
                        6379
                    ),
                    mongodb: readFirstNumber(
                        'storage cluster MongoDB port',
                        options.storageClusterMongoPort,
                        env.VOLT_DEV_STORAGE_CLUSTER_MONGO_PORT,
                        options.clusterMongoPort,
                        env.VOLT_DEV_CLUSTER_MONGO_PORT,
                        27017
                    ),
                    daemon: readFirstNumber(
                        'storage cluster daemon port',
                        options.storageClusterDaemonPort,
                        env.VOLT_DEV_STORAGE_CLUSTER_DAEMON_PORT,
                        options.clusterDaemonPort,
                        env.VOLT_DEV_CLUSTER_DAEMON_PORT,
                        8080
                    )
                },
                jupyterHostPortRange: {
                    start: 25000,
                    end: 25049
                }
            }),
            createClusterConfig({
                key: 'compute',
                servicePrefix: 'compute',
                role: TEAM_CLUSTER_ROLE.ComputeNode,
                name: resolveClusterName(
                    readFirstText(options.computeClusterName, env.VOLT_DEV_COMPUTE_CLUSTER_NAME),
                    'Local Dev Compute Node',
                    'Compute Node',
                    legacyClusterName
                ),
                installRoot: readFirstText(options.computeInstallRoot, env.VOLT_DEV_COMPUTE_CLUSTER_INSTALL_ROOT)
                    || path.posix.join(defaultInstallRoot, 'compute'),
                ports: {
                    minio: readFirstNumber(
                        'compute cluster MinIO port',
                        options.computeClusterMinioPort,
                        env.VOLT_DEV_COMPUTE_CLUSTER_MINIO_PORT,
                        9001
                    ),
                    redis: readFirstNumber(
                        'compute cluster Redis port',
                        options.computeClusterRedisPort,
                        env.VOLT_DEV_COMPUTE_CLUSTER_REDIS_PORT,
                        6380
                    ),
                    mongodb: readFirstNumber(
                        'compute cluster MongoDB port',
                        options.computeClusterMongoPort,
                        env.VOLT_DEV_COMPUTE_CLUSTER_MONGO_PORT,
                        27018
                    ),
                    daemon: readFirstNumber(
                        'compute cluster daemon port',
                        options.computeClusterDaemonPort,
                        env.VOLT_DEV_COMPUTE_CLUSTER_DAEMON_PORT,
                        8081
                    )
                },
                jupyterHostPortRange: {
                    start: 25050,
                    end: 25099
                }
            })
        ]
    };
};
