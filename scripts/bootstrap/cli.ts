import type { ParsedCliArgs } from './types.ts';
import { parseArgs } from 'node:util';

const toCamelCase = (value: string): string => {
    return value.replace(/-([a-z])/g, (_, char: string) => char.toUpperCase());
};

export const parseCliArgs = (argv: string[]): ParsedCliArgs => {
    const parsedArgs = parseArgs({
        args: argv,
        allowPositionals: true,
        strict: false,
        tokens: true
    });
    const options: Record<string, string> = {};

    parsedArgs.tokens.forEach((token, index) => {
        if (token.kind !== 'option') {
            return;
        }

        const nextToken = parsedArgs.tokens[index + 1];
        const value = token.value !== undefined
            ? token.value
            : nextToken?.kind === 'positional' && nextToken.index === token.index + 1
                ? nextToken.value
                : 'true';

        options[toCamelCase(token.name)] = String(value);
    });

    return {
        command: parsedArgs.positionals[0] || 'provision',
        options
    };
};
