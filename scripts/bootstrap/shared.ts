export { setTimeout as sleep } from 'node:timers/promises';

export const trimTrailingSlash = (value: string): string => value.replace(/\/+$/g, '');

export const normalizeName = (value: string): string => value.trim().toLowerCase();

export const readString = (value: unknown, context: string): string => {
    if (typeof value !== 'string' || value.trim().length === 0) {
        throw new Error(`Expected ${context} to be a non-empty string`);
    }

    return value.trim();
};

export const readOptionalString = (value: unknown): string | undefined => {
    if (typeof value !== 'string') {
        return undefined;
    }

    return value.trim() || undefined;
};

export const readObject = (value: unknown, context: string): Record<string, unknown> => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        throw new Error(`Expected ${context} to be an object`);
    }

    return value as Record<string, unknown>;
};

export const readArray = (value: unknown, context: string): unknown[] => {
    if (!Array.isArray(value)) {
        throw new Error(`Expected ${context} to be an array`);
    }

    return value;
};

export const toErrorMessage = (error: unknown): string =>
    error instanceof Error ? error.stack || error.message : String(error);
