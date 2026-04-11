import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { GeneratedArtifactWriter } from './bootstrap/artifact-writer.ts';
import { VoltLocalStackApiClient } from './bootstrap/api-client.ts';
import { parseCliArgs } from './bootstrap/cli.ts';
import { createBootstrapConfig } from './bootstrap/config.ts';
import { LocalStackProvisioner } from './bootstrap/provisioner.ts';
import type { BootstrapConfig, ProvisionedState, TrackedState } from './bootstrap/types.ts';
import { toErrorMessage, trimTrailingSlash } from './bootstrap/shared.ts';

const printProvisionSummary = (state: ProvisionedState, config: BootstrapConfig): void => {
    console.log('');
    console.log('Volt dev bootstrap complete');
    console.log(`Web: ${trimTrailingSlash(config.webUrl)}`);
    console.log(`API: ${trimTrailingSlash(config.apiUrl)}`);
    console.log(`User: ${config.devUser.email}`);
    console.log(`Password: ${config.devUser.password}`);
    console.log(`Team: ${state.team.name} (${state.team._id})`);

    for (const { clusterConfig, cluster } of state.clusters) {
        console.log(
            `Cluster [${clusterConfig.key}]: ${cluster.name} (${cluster._id}) role=${clusterConfig.role} status=${cluster.status}`
        );
    }

    console.log(`Cluster env files: ${config.outputDirectory}`);
};

const printClusterReadySummary = (state: TrackedState): void => {
    console.log('');
    console.log('Cluster daemons connected');

    for (const { clusterConfig, cluster } of state.clusters) {
        console.log(`Cluster [${clusterConfig.key}]: ${cluster.name} (${cluster._id}) status=${cluster.status}`);
    }
};

const main = async (): Promise<void> => {
    const { command, options } = parseCliArgs(process.argv.slice(2));
    const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
    const stackRoot = path.resolve(scriptDirectory, '..');
    const config = createBootstrapConfig({
        options,
        env: process.env,
        defaultOutputDirectory: path.join(stackRoot, '.generated', 'clusters')
    });

    const provisioner = new LocalStackProvisioner({
        apiClient: new VoltLocalStackApiClient(config),
        artifactWriter: new GeneratedArtifactWriter(config.outputDirectory),
        config
    });

    switch (command) {
        case 'provision': {
            const state = await provisioner.provision();
            printProvisionSummary(state, config);
            return;
        }

        case 'wait-cluster': {
            const state = await provisioner.waitForClusterConnection();
            printClusterReadySummary(state);
            return;
        }

        default:
            throw new Error(`Unknown command '${command}'`);
    }
};

main().catch((error) => {
    console.error(toErrorMessage(error));
    process.exit(1);
});
