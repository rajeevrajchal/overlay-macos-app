import type { CustomAtRules, Visitor } from 'lightningcss';

function flatten(obj: unknown | Record<string, unknown>, depth = 0): Record<string, unknown> {
	const toReturn: Record<string, unknown> = {};
	if (typeof obj !== 'object' || !obj) return {};

	const keys = Object.keys(obj);
	const values = Object.values(obj);

	for (let i = 0; i < keys.length; i++) {
		const key = keys[i];
		if (!Object.hasOwnProperty.call(obj, key)) continue;
		const val = values[i];

		if (typeof val === 'object' && val !== null) {
			if (depth > 4) {
				console.warn('FlattenObject: Max depth reached', key);
				continue;
			}
			const flatObject = flatten(val, depth + 1);
			for (const deeperKey in flatObject) {
				if (!flatObject.hasOwnProperty(deeperKey)) continue;
				const newKey = key + '-' + deeperKey;
				toReturn[newKey] = flatObject[deeperKey];
			}
		} else {
			toReturn[key] = val;
		}
	}

	return toReturn;
}

function flattenToEnvironment(obj: unknown | Record<string, unknown>) {
	if (typeof obj !== 'object' || !obj) return {};

	const flattened = flatten(obj);
	const result: Record<string, () => { raw: string }> = {};

	for (const key in flattened) {
		const value = flattened[key];
		result[`--${key}`] = () => ({ raw: `${value} ` });
	}

	return result;
}

export function environmentVariables({
	variables,
	breakpoints
}: {
	variables: unknown | Record<string, unknown>;
	breakpoints?: Record<string, string>;
}): Visitor<CustomAtRules> {
	return {
		EnvironmentVariable: flattenToEnvironment(variables),
		MediaQuery: (query) => {
			if (!breakpoints || !query.condition) return;
			if (query.condition.type !== 'feature') return;
			if (query.condition.value.type !== 'boolean') return;

			const key = query.condition.value.name.replace(/^--/, '');
			if (breakpoints[key]) {
				return { raw: breakpoints[key] };
			} else {
				console.warn('Custom breakpoint not found: ' + query.condition.value.name);
			}
		}
	};
}
