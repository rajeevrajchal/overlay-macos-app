<script lang="ts">
	import '@styles/css/reset.css';
	import '@styles/css/global.css';

	import DocumentHead from '@components/document-head.svelte';
	import Debug from '@modules/tweak-pane/debug.svelte';

	let { children } = $props();
</script>

<DocumentHead />
<main class="app-content">
	{@render children()}
</main>
<Debug />
