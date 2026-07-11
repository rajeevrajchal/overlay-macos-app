<script lang="ts">
	import { onMount } from 'svelte';
	import { BreakpointsPx, Variables } from '@theme';

	interface Props {
		visible: boolean;
		targetSelector?: string;
		columnsMobile?: number;
		columnsTablet?: number;
		columnsDesktop?: number;
		columnGapMobile?: number;
		columnGapTablet?: number;
		columnGapDesktop?: number;
		opacity?: number;
		color?: string;
	}

	let {
		visible,
		targetSelector = '.app-content',
		columnsMobile = Number(Variables.grid['columns-mobile']),
		columnsTablet = Number(Variables.grid['columns-tablet']),
		columnsDesktop = Number(Variables.grid['columns-desktop']),
		columnGapMobile = Number.parseFloat(Variables.grid['gap-mobile']),
		columnGapTablet = Number.parseFloat(Variables.grid['gap-tablet']),
		columnGapDesktop = Number.parseFloat(Variables.grid['gap-desktop']),
		opacity = 0.22,
		color = 'var(--color-accent)'
	}: Props = $props();

	let frameLeft = $state(0);
	let frameWidth = $state(0);
	let viewportWidth = $state(0);

	let activeColumns = $derived(
		viewportWidth < BreakpointsPx.md
			? columnsMobile
			: viewportWidth < BreakpointsPx.lg
				? columnsTablet
				: columnsDesktop
	);
	let activeGap = $derived(
		viewportWidth < BreakpointsPx.md
			? columnGapMobile
			: viewportWidth < BreakpointsPx.lg
				? columnGapTablet
				: columnGapDesktop
	);
	let columnWidth = $derived(
		Math.max(
			0,
			(frameWidth - (Math.max(activeColumns, 1) - 1) * activeGap) / Math.max(activeColumns, 1)
		)
	);

	onMount(() => {
		const targetElement = document.querySelector(targetSelector);
		if (!(targetElement instanceof HTMLElement)) return;

		const updateFrame = () => {
			const rect = targetElement.getBoundingClientRect();
			frameLeft = rect.left;
			frameWidth = rect.width;
		};

		const updateViewport = () => {
			viewportWidth = window.innerWidth;
		};

		const observer = new ResizeObserver(updateFrame);

		updateViewport();
		updateFrame();
		observer.observe(targetElement);
		window.addEventListener('resize', updateViewport);

		return () => {
			observer.disconnect();
			window.removeEventListener('resize', updateViewport);
		};
	});
</script>

<div
	class="debug-layout-overlay"
	style={`
		--debug-layout-left: ${frameLeft}px;
		--debug-layout-width: ${frameWidth}px;
		--debug-layout-opacity: ${visible ? opacity : 0};
		--debug-layout-gap: ${activeGap}px;
		--debug-layout-column: ${columnWidth}px;
		--debug-layout-color: ${color};
	`}
></div>

<style>
	.debug-layout-overlay {
		position: fixed;
		top: 0;
		left: var(--debug-layout-left);
		width: var(--debug-layout-width);
		height: 100dvh;
		pointer-events: none;
		z-index: 998;
		opacity: var(--debug-layout-opacity);
		transition: opacity env(--transition-fast);
		background-image: repeating-linear-gradient(
			to right,
			color-mix(in oklab, var(--debug-layout-color) 35%, transparent) 0,
			color-mix(in oklab, var(--debug-layout-color) 35%, transparent) var(--debug-layout-column),
			transparent var(--debug-layout-column),
			transparent calc(var(--debug-layout-column) + var(--debug-layout-gap))
		);
		background-size: calc(var(--debug-layout-column) + var(--debug-layout-gap)) 100%;
		background-position: left top;
	}
</style>
