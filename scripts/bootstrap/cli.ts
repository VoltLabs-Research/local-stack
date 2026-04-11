import type { ParsedCliArgs } from './types.ts';

export const parseCliArgs = (argv: string[]): ParsedCliArgs => {
    const options: Record<string, string> = {};
    let command = 'provision';

    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (!arg.startsWith('--')) {
            command = arg;
            continue;
        }

        const [rawKey, inlineValue] = arg.slice(2).split('=');
        const key = rawKey.replace(/-([a-z])/g, (_, char: string) => char.toUpperCase());

        if (inlineValue !== undefined) {
            options[key] = inlineValue;
            continue;
        }

        const nextValue = argv[index + 1];
        if (nextValue === undefined || nextValue.startsWith('--')) {
            options[key] = 'true';
            continue;
        }

        options[key] = nextValue;
        index += 1;
    }

    return {
        command,
        options
    };
};
