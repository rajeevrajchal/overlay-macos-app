<script lang="ts">
	import { onMount } from 'svelte';

	interface Props {
		visible: boolean;
		size?: number;
		opacity?: number;
		color?: string;
	}

	let { visible, size = 32, opacity = 0.8, color = 'rgba(255, 0, 0)' }: Props = $props();

	let vw = $state(0);
	let vh = $state(0);

	const verticalLines = $derived.by(() => {
		if (!vw) return [];
		const count = Math.floor(vw / size);
		const step = vw / count; // recalculate step to fill exactly
		return Array.from({ length: count + 1 }, (_, i) => i * step);
	});

	const horizontalLines = $derived.by(() => {
		if (!vh) return [];
		const count = Math.floor(vh / size);
		const step = vh / count;
		return Array.from({ length: count + 1 }, (_, i) => i * step);
	});

	const resolvedOpacity = $derived(visible ? opacity : 0);

	onMount(() => {
		const obs = new ResizeObserver((entries) => {
			for (const entry of entries) {
				vw = entry.contentRect.width;
				vh = entry.contentRect.height;
			}
		});
		obs.observe(document.documentElement);

		// Initial size
		vw = window.innerWidth;
		vh = window.innerHeight;

		return () => obs.disconnect();
	});
</script>

<svg
	class="debug-grid-overlay"
	style:opacity={resolvedOpacity}
	viewBox="0 0 {vw} {vh}"
	xmlns="http://www.w3.org/2000/svg"
	aria-hidden="true"
>
	<!-- Vertical lines -->
	{#each verticalLines as x (x)}
		<line x1={x} y1={0} x2={x} y2={vh} stroke={color} stroke-width="1" />
	{/each}

	<!-- Horizontal lines -->
	{#each horizontalLines as y (y)}
		<line x1={0} y1={y} x2={vw} y2={y} stroke={color} stroke-width="1" />
	{/each}
</svg>

<style>
	.debug-grid-overlay {
		position: fixed;
		inset: 0;
		width: 100%;
		height: 100%;
		pointer-events: none;
		z-index: 9999;
		transition: opacity var(--transition-fast, 150ms ease);
	}
</style>
