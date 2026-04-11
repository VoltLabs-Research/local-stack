import {
    TEAM_CLUSTER_ROLE,
    TEAM_CLUSTER_STATUS,
    type BootstrapConfig,
    type CreatedClusterRecord,
    type RevealedClusterServices,
    type TeamClusterRecord,
    type TeamClusterRole,
    type TeamClusterStatus,
    type TeamRecord,
    type UserSession
} from './types.ts';
import {
    readArray,
    readObject,
    readOptionalString,
    readString,
    sleep,
    trimTrailingSlash
} from './shared.ts';

interface RequestOptions {
    method?: string;
    token?: string;
    body?: unknown;
    allowStatuses?: readonly number[];
}

interface RequestResult {
    response: Response;
    payload: unknown;
}

const VALID_TEAM_CLUSTER_STATUSES = new Set<TeamClusterStatus>(Object.values(TEAM_CLUSTER_STATUS));
const VALID_TEAM_CLUSTER_ROLES = new Set<TeamClusterRole>(Object.values(TEAM_CLUSTER_ROLE));

export class ApiError extends Error {
    readonly statusCode: number;
    readonly payload: unknown;

    constructor(message: string, statusCode: number, payload: unknown) {
        super(message);
        this.name = 'ApiError';
        this.statusCode = statusCode;
        this.payload = payload;
    }
}

const parseResponseBody = async (response: Response): Promise<unknown> => {
    const contentType = response.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
        return response.json();
    }

    return {
        status: response.ok ? 'success' : 'error',
        message: await response.text()
    };
};

const readEnvelopeData = (payload: unknown, context: string): unknown => {
    const record = readObject(payload, `${context} response payload`);
    return record.data;
};

const readTeamRecord = (value: unknown, context: string): TeamRecord => {
    const record = readObject(value, context);

    return {
        _id: readString(record._id, `${context}._id`),
        name: readString(record.name, `${context}.name`)
    };
};

const readTeamClusterRoleConfig = (value: unknown): TeamClusterRecord['roleConfig'] | undefined => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        return undefined;
    }

    const record = value as Record<string, unknown>;
    const desiredRole = readOptionalString(record.desiredRole);
    if (!desiredRole) {
        return undefined;
    }

    if (!VALID_TEAM_CLUSTER_ROLES.has(desiredRole as TeamClusterRole)) {
        throw new Error(`Unexpected team cluster role '${desiredRole}'`);
    }

    return {
        desiredRole: desiredRole as TeamClusterRole
    };
};

const readTeamClusterRecord = (value: unknown, context: string): TeamClusterRecord => {
    const record = readObject(value, context);
    const status = readString(record.status, `${context}.status`);
    if (!VALID_TEAM_CLUSTER_STATUSES.has(status as TeamClusterStatus)) {
        throw new Error(`Unexpected team cluster status '${status}' in ${context}`);
    }

    return {
        _id: readString(record._id, `${context}._id`),
        name: readString(record.name, `${context}.name`),
        status: status as TeamClusterStatus,
        roleConfig: readTeamClusterRoleConfig(record.roleConfig)
    };
};

const unwrapTeamCluster = (value: unknown, context: string): TeamClusterRecord => {
    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        const record = value as Record<string, unknown>;
        if (typeof record._id === 'string') {
            return readTeamClusterRecord(record, context);
        }

        if (record.teamCluster !== undefined) {
            return readTeamClusterRecord(record.teamCluster, `${context}.teamCluster`);
        }
    }

    throw new Error(`Expected team cluster payload in ${context}`);
};

const readClusterServiceCredentials = (value: unknown, context: string): { username: string; password: string; } => {
    const record = readObject(value, context);
    return {
        username: readString(record.username, `${context}.username`),
        password: readString(record.password, `${context}.password`)
    };
};

const readRevealedClusterServices = (value: unknown, context: string): RevealedClusterServices => {
    const record = readObject(value, context);
    const daemonRecord = readObject(record.daemon, `${context}.daemon`);

    return {
        minio: readClusterServiceCredentials(record.minio, `${context}.minio`),
        mongodb: readClusterServiceCredentials(record.mongodb, `${context}.mongodb`),
        redis: readClusterServiceCredentials(record.redis, `${context}.redis`),
        daemon: {
            password: readString(daemonRecord.password, `${context}.daemon.password`)
        }
    };
};

const readErrorMessage = (payload: unknown): string | undefined => {
    if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
        return undefined;
    }

    const message = (payload as Record<string, unknown>).message;
    return typeof message === 'string' && message.trim().length > 0
        ? message.trim()
        : undefined;
};

export class VoltLocalStackApiClient {
    readonly #config: BootstrapConfig;

    constructor(config: BootstrapConfig) {
        this.#config = config;
    }

    async request(pathname: string, options: RequestOptions = {}): Promise<RequestResult> {
        const response = await fetch(`${trimTrailingSlash(this.#config.apiUrl)}${pathname}`, {
            method: options.method || 'GET',
            headers: {
                ...(options.body ? { 'Content-Type': 'application/json' } : {}),
                ...(options.token ? { Authorization: `Bearer ${options.token}` } : {})
            },
            ...(options.body ? { body: JSON.stringify(options.body) } : {})
        });

        const payload = await parseResponseBody(response);
        if (response.ok || options.allowStatuses?.includes(response.status)) {
            return { response, payload };
        }

        throw new ApiError(
            readErrorMessage(payload) || `Request failed with status ${response.status}`,
            response.status,
            payload
        );
    }

    async waitForApi(): Promise<void> {
        const deadline = Date.now() + this.#config.timeoutMs;

        while (Date.now() < deadline) {
            try {
                await this.request('/api/auth/guest-identity?seed=volt-dev');
                return;
            } catch {
                await sleep(this.#config.pollIntervalMs);
            }
        }

        throw new Error(`Volt API did not become ready within ${this.#config.timeoutMs}ms`);
    }

    async signUpOrSignIn(): Promise<UserSession> {
        const signUpResult = await this.request('/api/auth/users', {
            method: 'POST',
            body: {
                email: this.#config.devUser.email,
                password: this.#config.devUser.password,
                firstName: this.#config.devUser.firstName,
                lastName: this.#config.devUser.lastName
            },
            allowStatuses: [409]
        });

        if (signUpResult.response.ok) {
            const data = readObject(readEnvelopeData(signUpResult.payload, 'signUp'), 'signUp.data');
            return {
                token: readString(data.token, 'signUp.data.token'),
                user: data.user
            };
        }

        const signInResult = await this.request('/api/auth/sessions', {
            method: 'POST',
            body: {
                email: this.#config.devUser.email,
                password: this.#config.devUser.password
            }
        });

        const data = readObject(readEnvelopeData(signInResult.payload, 'signIn'), 'signIn.data');
        return {
            token: readString(data.token, 'signIn.data.token'),
            user: data.user
        };
    }

    async listUserTeams(token: string): Promise<TeamRecord[]> {
        const result = await this.request('/api/teams', { token });
        const data = readArray(readEnvelopeData(result.payload, 'listUserTeams'), 'listUserTeams.data');
        return data.map((team, index) => readTeamRecord(team, `listUserTeams.data[${index}]`));
    }

    async createTeam(token: string, input: { name: string; description: string; }): Promise<TeamRecord> {
        const result = await this.request('/api/teams', {
            method: 'POST',
            token,
            body: input
        });

        return readTeamRecord(readEnvelopeData(result.payload, 'createTeam'), 'createTeam.data');
    }

    async listTeamClusters(token: string, teamId: string, search = ''): Promise<TeamClusterRecord[]> {
        const query = new URLSearchParams({
            page: '1',
            limit: '100'
        });
        const trimmedSearch = search.trim();
        if (trimmedSearch.length > 0) {
            query.set('search', trimmedSearch);
        }

        const result = await this.request(`/api/teams/${teamId}/clusters?${query.toString()}`, { token });
        const data = readArray(readEnvelopeData(result.payload, 'listTeamClusters'), 'listTeamClusters.data');
        return data.map((cluster, index) => readTeamClusterRecord(cluster, `listTeamClusters.data[${index}]`));
    }

    async createCluster(token: string, teamId: string, clusterName: string): Promise<CreatedClusterRecord> {
        const result = await this.request(`/api/teams/${teamId}/clusters`, {
            method: 'POST',
            token,
            body: {
                name: clusterName
            }
        });

        const data = readObject(readEnvelopeData(result.payload, 'createCluster'), 'createCluster.data');
        return {
            teamCluster: unwrapTeamCluster(data, 'createCluster.data'),
            enrollmentToken: readOptionalString(data.enrollmentToken) || null
        };
    }

    async updateClusterRole(token: string, teamId: string, teamClusterId: string, role: TeamClusterRole): Promise<void> {
        await this.request(`/api/teams/${teamId}/clusters/${teamClusterId}/role`, {
            method: 'PATCH',
            token,
            body: { role }
        });
    }

    async regenerateEnrollmentToken(token: string, teamId: string, teamClusterId: string): Promise<string | null> {
        const result = await this.request(
            `/api/teams/${teamId}/clusters/${teamClusterId}/enrollment-token/regenerate`,
            {
                method: 'POST',
                token,
                allowStatuses: [409]
            }
        );

        if (result.response.status === 409) {
            return null;
        }

        const data = readObject(readEnvelopeData(result.payload, 'regenerateEnrollmentToken'), 'regenerateEnrollmentToken.data');
        return readOptionalString(data.enrollmentToken) || null;
    }

    async getClusterById(token: string, teamId: string, teamClusterId: string): Promise<TeamClusterRecord> {
        const result = await this.request(`/api/teams/${teamId}/clusters/${teamClusterId}`, { token });
        return unwrapTeamCluster(readEnvelopeData(result.payload, 'getClusterById'), 'getClusterById.data');
    }

    async revealClusterCredentials(token: string, teamId: string, teamClusterId: string, password: string): Promise<RevealedClusterServices> {
        const result = await this.request(`/api/teams/${teamId}/clusters/${teamClusterId}/credentials/reveal`, {
            method: 'POST',
            token,
            body: { password }
        });

        const data = readObject(readEnvelopeData(result.payload, 'revealClusterCredentials'), 'revealClusterCredentials.data');
        return readRevealedClusterServices(data.services, 'revealClusterCredentials.data.services');
    }

    async persistInstallMetadata(teamClusterId: string, input: {
        daemonPassword: string;
        installRoot: string;
        ports: {
            minio: number;
            redis: number;
            mongodb: number;
            daemon: number;
        };
    }): Promise<void> {
        await this.request(`/api/team-clusters/${teamClusterId}/install-manifest`, {
            method: 'POST',
            body: {
                daemonPassword: input.daemonPassword,
                installRoot: input.installRoot,
                ports: input.ports
            }
        });
    }
}
