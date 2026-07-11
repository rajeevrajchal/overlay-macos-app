<script lang="ts">
	import { Checkbox, File, Pane, Separator, Slider, type FileValue } from 'svelte-tweakpane-ui';
	import { tweakPaneStore } from '../tweak-pane-state.svelte';

	let designFile = $state<FileValue>(undefined);

	$effect(() => {
		if (designFile instanceof globalThis.File) {
			const url = URL.createObjectURL(designFile);
			tweakPaneStore.designOverlayImageUrl = url;
			return () => URL.revokeObjectURL(url);
		} else {
			tweakPaneStore.designOverlayImageUrl = '';
		}
	});
</script>

<Pane position="draggable" title="Tweak" expanded={true} width={300}>
	<Checkbox bind:value={tweakPaneStore.showDebugGrid} label="Debug Grid" />
	<Checkbox bind:value={tweakPaneStore.showDebugLayout} label="Debug Layout" />
	<Slider
		bind:value={tweakPaneStore.contentMaxWidth}
		label="Max Width"
		min={640}
		max={1440}
		step={20}
	/>
	<Separator />
	<File bind:value={designFile} label="Image" extensions={['.png', '.jpg', '.jpeg']} rows={2} />
	<Slider
		bind:value={tweakPaneStore.designOverlayOpacity}
		label="Opacity"
		min={0}
		max={1}
		step={0.01}
		disabled={!tweakPaneStore.designOverlayImageUrl}
	/>
</Pane>
