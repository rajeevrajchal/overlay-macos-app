<script lang="ts">
	import { page } from '$app/state';
	import favicon from '@assets/favicon.svg';

	const name = 'App Name';
</script>

<svelte:head>
	<link rel="icon" href={favicon} />

	{#if page.data.title}
		<title>{page.data.title}</title>
	{:else}
		<title>{name}</title>
	{/if}
</svelte:head>
