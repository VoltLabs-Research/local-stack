import { FAILURE_TEAM_CLUSTER_STATUSES, TEAM_CLUSTER_STATUS, type BootstrapConfig, type ProvisionedClusterRecord, type ProvisionedState, type TeamClusterRecord, type TeamRecord, type TrackedClusterRecord, type TrackedState } from './types.ts';
import { normalizeName, sleep } from './shared.ts';
import { VoltLocalStackApiClient } from './api-client.ts';
import { GeneratedArtifactWriter } from './artifact-writer.ts';

export class LocalStackProvisioner {
    readonly #apiClient: VoltLocalStackApiClient;
    readonly #artifactWriter: GeneratedArtifactWriter;
    readonly #config: BootstrapConfig;

    constructor(input: {
        apiClient: VoltLocalStackApiClient;
        artifactWriter: GeneratedArtifactWriter;
        config: BootstrapConfig;
    }) {
        this.#apiClient = input.apiClient;
        this.#artifactWriter = input.artifactWriter;
        this.#config = input.config;
    }

    async provision(): Promise<ProvisionedState> {
        return this.ensureProvisionedState(true);
    }

    async waitForClusterConnection(): Promise<TrackedState> {
        const state = await this.getExistingProvisionedState();
        const deadline = Date.now() + this.#config.timeoutMs;

        while (Date.now() < deadline) {
            const connectedClusters: TrackedClusterRecord[] = [];

            for (const provisionedCluster of state.clusters) {
                const cluster = await this.#apiClient.getClusterById(
                    state.token,
                    state.team._id,
                    provisionedCluster.cluster._id
                );

                if (FAILURE_TEAM_CLUSTER_STATUSES.has(cluster.status)) {
                    throw new Error(`Cluster '${cluster.name}' entered a failure state: ${cluster.status}`);
                }

                connectedClusters.push({
                    ...provisionedCluster,
                    cluster
                });
            }

            if (connectedClusters.every(({ cluster }) => cluster.status === TEAM_CLUSTER_STATUS.Connected)) {
                return {
                    ...state,
                    clusters: connectedClusters
                };
            }

            await sleep(this.#config.pollIntervalMs);
        }

        throw new Error(`Not all dev clusters reached '${TEAM_CLUSTER_STATUS.Connected}' within ${this.#config.timeoutMs}ms`);
    }

    private async ensureProvisionedState(writeFiles: boolean): Promise<ProvisionedState> {
        await this.#apiClient.waitForApi();

        const session = await this.#apiClient.signUpOrSignIn();
        const team = await this.getOrCreateTeam(session.token);
        const clusters: ProvisionedClusterRecord[] = [];

        for (const clusterConfig of this.#config.clusters) {
            clusters.push(await this.ensureProvisionedClusterState(session.token, team, clusterConfig));
        }

        const state: ProvisionedState = {
            token: session.token,
            user: session.user,
            team,
            clusters
        };

        if (writeFiles) {
            await this.#artifactWriter.writeProvisionedState(state, this.#config);
        }

        return state;
    }

    private async getExistingProvisionedState(): Promise<TrackedState> {
        await this.#apiClient.waitForApi();

        const session = await this.#apiClient.signUpOrSignIn();
        const team = await this.getOrCreateTeam(session.token);
        const clusters: TrackedClusterRecord[] = [];

        for (const clusterConfig of this.#config.clusters) {
            const cluster = await this.findClusterByName(session.token, team._id, clusterConfig.name);
            if (!cluster) {
                throw new Error(`Cluster '${clusterConfig.name}' was not found. Run the bootstrap provision step first.`);
            }

            clusters.push({
                clusterConfig,
                cluster
            });
        }

        return {
            token: session.token,
            user: session.user,
            team,
            clusters
        };
    }

    private async getOrCreateTeam(token: string): Promise<TeamRecord> {
        const existingTeam = await this.findTeamByName(token, this.#config.team.name);
        if (existingTeam) {
            return existingTeam;
        }

        return this.#apiClient.createTeam(token, {
            name: this.#config.team.name,
            description: this.#config.team.description
        });
    }

    private async findTeamByName(token: string, teamName: string): Promise<TeamRecord | null> {
        const teams = await this.#apiClient.listUserTeams(token);
        return teams.find((team) => normalizeName(team.name) === normalizeName(teamName)) || null;
    }

    private async findClusterByName(token: string, teamId: string, clusterName: string): Promise<TeamClusterRecord | null> {
        const clusters = await this.#apiClient.listTeamClusters(token, teamId, clusterName);
        return clusters.find((cluster) => normalizeName(cluster.name) === normalizeName(clusterName)) || null;
    }

    private async ensureProvisionedClusterState(
        token: string,
        team: TeamRecord,
        clusterConfig: BootstrapConfig['clusters'][number]
    ): Promise<ProvisionedClusterRecord> {
        let cluster = await this.findClusterByName(token, team._id, clusterConfig.name);
        let enrollmentToken: string | null = null;

        if (!cluster) {
            const createdCluster = await this.#apiClient.createCluster(token, team._id, clusterConfig.name);
            cluster = createdCluster.teamCluster;
            enrollmentToken = createdCluster.enrollmentToken;
        } else if (cluster.status !== TEAM_CLUSTER_STATUS.Connected) {
            enrollmentToken = await this.#apiClient.regenerateEnrollmentToken(token, team._id, cluster._id);
        }

        if (cluster.roleConfig?.desiredRole !== clusterConfig.role) {
            await this.#apiClient.updateClusterRole(token, team._id, cluster._id, clusterConfig.role);
        }

        const services = await this.#apiClient.revealClusterCredentials(
            token,
            team._id,
            cluster._id,
            this.#config.devUser.password
        );

        await this.#apiClient.persistInstallMetadata(cluster._id, {
            daemonPassword: services.daemon.password,
            installRoot: clusterConfig.installRoot,
            ports: clusterConfig.ports
        });

        cluster = await this.#apiClient.getClusterById(token, team._id, cluster._id);

        return {
            clusterConfig,
            cluster,
            services,
            enrollmentToken
        };
    }
}
