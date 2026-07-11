import { DEFAULT_TWEAK_STATE, type TweakState } from './tweak-state';

class TweakPaneStore {
	public showDebugGrid = $state<boolean>(DEFAULT_TWEAK_STATE.showDebugGrid);
	public showDebugLayout = $state<boolean>(DEFAULT_TWEAK_STATE.showDebugLayout);
	public contentMaxWidth = $state<number>(DEFAULT_TWEAK_STATE.contentMaxWidth);
	public designOverlayImageUrl = $state<string>(DEFAULT_TWEAK_STATE.designOverlayImageUrl);
	public designOverlayOpacity = $state<number>(DEFAULT_TWEAK_STATE.designOverlayOpacity);

	applyState(state: TweakState): void {
		this.showDebugGrid = state.showDebugGrid;
		this.showDebugLayout = state.showDebugLayout;
		this.contentMaxWidth = state.contentMaxWidth;
		this.designOverlayImageUrl = state.designOverlayImageUrl;
		this.designOverlayOpacity = state.designOverlayOpacity;
	}
}

export const tweakPaneStore = new TweakPaneStore();
