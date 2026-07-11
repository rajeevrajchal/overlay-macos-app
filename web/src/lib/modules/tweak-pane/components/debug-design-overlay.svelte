<script lang="ts">
	let x = $state(0);
	let y = $state(0);
	let isDragging = $state(false);

	let {
		imageUrl,
		opacity
	}: {
		imageUrl: string;
		opacity: number;
	} = $props();

	const onPointerDown = (e: PointerEvent) => {
		if (e.button !== 0) return;
		isDragging = true;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
	};

	const onPointerMove = (e: PointerEvent) => {
		if (!isDragging) return;
		x += e.movementX;
		y += e.movementY;
	};

	const onPointerUp = (e: PointerEvent) => {
		isDragging = false;
		(e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
	};
</script>

{#if imageUrl}
	<div class="overlay">
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div
			class="image-frame"
			style:transform="translate3d({x}px, {y}px, 0)"
			style:opacity
			onpointerdown={onPointerDown}
			onpointermove={onPointerMove}
			onpointerup={onPointerUp}
			onpointercancel={onPointerUp}
		>
			<img src={imageUrl} alt="design overlay" draggable="false" />
		</div>
	</div>
{/if}

<style>
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 998;
		pointer-events: none;
	}

	.image-frame {
		position: absolute;
		top: 0;
		left: 0;
		display: inline-block;
		pointer-events: auto;
		cursor: grab;
		user-select: none;
		touch-action: none;
		will-change: transform;
		border: 1px dashed rgba(255, 0, 0, 0.4);
	}

	.image-frame:active {
		cursor: grabbing;
	}

	img {
		display: block;
		-webkit-user-drag: none;
	}
</style>
