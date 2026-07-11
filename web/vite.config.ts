import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { composeVisitors, Features } from 'lightningcss';
import { environmentVariables } from './vite-plugins/lightningcss';
import { Variables, Breakpoints } from './src/styles/theme/variables';

export default defineConfig({
	css: {
		transformer: 'lightningcss',
		lightningcss: {
			include: Features.Nesting,
			drafts: { customMedia: true },
			visitor: composeVisitors([
				environmentVariables({
					variables: Variables,
					breakpoints: Breakpoints
				})
			])
		}
	},
	plugins: [sveltekit()],
	build: {
		rolldownOptions: {
			output: {}
		}
	}
});
