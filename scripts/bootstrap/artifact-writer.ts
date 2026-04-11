import fs from 'node:fs/promises';
import path from 'node:path';
import type { BootstrapConfig, BootstrapStateFile, ProvisionedClusterRecord, ProvisionedState } from './types.ts';
import { trimTrailingSlash } from './shared.ts';

const joinLines = (lines: string[]): string => {
    return `${lines.join('\n')}\n`;
};

const buildDaemonEnvLines = (input: {
    config: BootstrapConfig;
    state: ProvisionedState;
    provisionedCluster: ProvisionedClusterRecord;
}): string[] => {
    const { config, state, provisionedCluster } = input;
    const { clusterConfig, cluster, services, enrollmentToken } = provisionedCluster;

    const lines = [
        `NODE_ENV=${config.daemonNodeEnv}`,
        'HOST=0.0.0.0',
        `PORT=${clusterConfig.ports.daemon}`,
        `TEAM_ID=${state.team._id}`,
        `TEAM_CLUSTER_ID=${cluster._id}`,
        `TEAM_CLUSTER_DAEMON_PASSWORD=${services.daemon.password}`,
        `TEAM_CLUSTER_HEALTHCHECK_PATH=/api/team-clusters/${cluster._id}/healthcheck`,
        `TEAM_CLUSTER_INSTALL_ROOT=${clusterConfig.installRoot}`,
        'TEAM_CLUSTER_DAEMON_DISTRIBUTION_MODE=build',
        'TEAM_CLUSTER_HEARTBEAT_INTERVAL_MS=10000',
        'TEAM_CLUSTER_METRICS_INTERVAL_MS=3000',
        'MINIO_USE_SSL=false',
        `MINIO_ENDPOINT=http://${clusterConfig.servicePrefix}-minio:9000`,
        `MINIO_ACCESS_KEY=${services.minio.username}`,
        `MINIO_SECRET_KEY=${services.minio.password}`,
        `MONGODB_URI=mongodb://${services.mongodb.username}:${services.mongodb.password}@${clusterConfig.servicePrefix}-mongodb:27017/volt?authSource=admin`,
        `REDIS_HOST=${clusterConfig.servicePrefix}-redis`,
        'REDIS_PORT=6379',
        `REDIS_USERNAME=${services.redis.username}`,
        `REDIS_PASSWORD=${services.redis.password}`,
        `VOLT_CLOUD_URL=${trimTrailingSlash(config.internalApiUrl)}`,
        `VOLT_CLOUD_DAEMON_SOCKET_URL=${trimTrailingSlash(config.internalApiUrl)}`,
        'VOLT_CLUSTER_INSTALL_MANIFEST_VERSION=dev-local',
        `JUPYTER_HOST_PORT_RANGE_START=${clusterConfig.jupyterHostPortRange.start}`,
        `JUPYTER_HOST_PORT_RANGE_END=${clusterConfig.jupyterHostPortRange.end}`,
        'JUPYTER_PUBLIC_BASE_PATH=/api/notebooks/proxy',
        'TAILSCALE_ENABLED=false',
        'TEAM_CLUSTER_TAILSCALE_REQUIRED=false',
        'TEAM_CLUSTER_OBJECT_GATEWAY_BIND_HOST=0.0.0.0',
        'TEAM_CLUSTER_OBJECT_GATEWAY_PORT=9080',
        'TEAM_CLUSTER_OBJECT_GATEWAY_DIRECT_ONLY=false'
    ];

    if (enrollmentToken) {
        lines.push(`TEAM_CLUSTER_ENROLLMENT_TOKEN=${enrollmentToken}`);
    }

    return lines;
};

const buildBootstrapStateFile = (state: ProvisionedState, config: BootstrapConfig): BootstrapStateFile => {
    return {
        generatedAt: new Date().toISOString(),
        user: {
            email: config.devUser.email
        },
        team: {
            id: state.team._id,
            name: state.team.name
        },
        clusters: state.clusters.map(({ clusterConfig, cluster }) => ({
            key: clusterConfig.key,
            role: clusterConfig.role,
            id: cluster._id,
            name: cluster.name,
            status: cluster.status,
            envDirectory: clusterConfig.key
        })),
        urls: {
            api: trimTrailingSlash(config.apiUrl),
            web: trimTrailingSlash(config.webUrl),
            internalApi: trimTrailingSlash(config.internalApiUrl)
        }
    };
};

export class GeneratedArtifactWriter {
    readonly #outputDirectory: string;

    constructor(outputDirectory: string) {
        this.#outputDirectory = outputDirectory;
    }

    async writeProvisionedState(state: ProvisionedState, config: BootstrapConfig): Promise<void> {
        await this.ensureDirectory();

        for (const provisionedCluster of state.clusters) {
            const clusterDirectory = provisionedCluster.clusterConfig.key;
            await this.ensureDirectory(clusterDirectory);

            await this.writeFile(
                path.join(clusterDirectory, 'minio.env'),
                joinLines([
                    `MINIO_ROOT_USER=${provisionedCluster.services.minio.username}`,
                    `MINIO_ROOT_PASSWORD=${provisionedCluster.services.minio.password}`
                ])
            );

            await this.writeFile(
                path.join(clusterDirectory, 'mongodb.env'),
                joinLines([
                    `MONGO_INITDB_ROOT_USERNAME=${provisionedCluster.services.mongodb.username}`,
                    `MONGO_INITDB_ROOT_PASSWORD=${provisionedCluster.services.mongodb.password}`,
                    'MONGO_INITDB_DATABASE=volt'
                ])
            );

            await this.writeFile(
                path.join(clusterDirectory, 'redis.env'),
                joinLines([
                    `REDIS_USERNAME=${provisionedCluster.services.redis.username}`,
                    `REDIS_PASSWORD=${provisionedCluster.services.redis.password}`
                ])
            );

            await this.writeFile(
                path.join(clusterDirectory, 'redis.acl'),
                joinLines([
                    'user default off',
                    `user ${provisionedCluster.services.redis.username} on >${provisionedCluster.services.redis.password} ~* &* +@all`
                ])
            );

            await this.writeFile(
                path.join(clusterDirectory, 'daemon.env'),
                joinLines(buildDaemonEnvLines({
                    config,
                    state,
                    provisionedCluster
                }))
            );
        }

        await this.writeFile(
            'bootstrap-state.json',
            `${JSON.stringify(buildBootstrapStateFile(state, config), null, 2)}\n`
        );
    }

    private async ensureDirectory(relativePath = '.'): Promise<void> {
        await fs.mkdir(path.join(this.#outputDirectory, relativePath), {
            recursive: true
        });
    }

    private async writeFile(relativePath: string, contents: string): Promise<void> {
        await fs.writeFile(path.join(this.#outputDirectory, relativePath), contents, 'utf8');
    }
}
