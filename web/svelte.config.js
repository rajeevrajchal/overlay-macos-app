import adapter from '@sveltejs/adapter-auto';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	kit: {
		adapter: adapter(),
		alias: {
			'@styles': './src/styles',
			'@theme': './src/styles/theme',
			'@components': './src/lib/components',
			'@assets': './src/lib/assets',
			'@modules': './src/lib/modules'
		}
	}
};

export default config;
