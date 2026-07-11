<script lang="ts">
	import { dev } from '$app/environment';
	import DebugDesignOverlay from './components/debug-design-overlay.svelte';
	import DebugGridOverlay from './components/debug-grid-overlay.svelte';
	import DebugLayoutOverlay from './components/debug-layout-overlay.svelte';
	import TweakPane from './components/tweak-pane.svelte';
	import { tweakPaneStore } from './tweak-pane-state.svelte.ts';
</script>

{#if dev}
	<DebugGridOverlay visible={tweakPaneStore.showDebugGrid} />
	<DebugLayoutOverlay visible={tweakPaneStore.showDebugLayout} targetSelector=".app-content" />
	<DebugDesignOverlay
		imageUrl={tweakPaneStore.designOverlayImageUrl}
		opacity={tweakPaneStore.designOverlayOpacity}
	/>
	<TweakPane />
{/if}
