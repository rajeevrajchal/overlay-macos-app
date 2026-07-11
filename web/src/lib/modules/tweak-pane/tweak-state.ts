export interface TweakState {
	showDebugGrid: boolean;
	showDebugLayout: boolean;
	contentMaxWidth: number;
	designOverlayImageUrl: string;
	designOverlayOpacity: number;
}

export const TWEAK_STORAGE_KEY = 'techarchive:tweak-state:v1';

export const DEFAULT_TWEAK_STATE: TweakState = {
	showDebugGrid: false,
	showDebugLayout: false,
	contentMaxWidth: 1440,
	designOverlayImageUrl: '',
	designOverlayOpacity: 0.4
};

function clamp(value: number, min: number, max: number): number {
	return Math.min(max, Math.max(min, value));
}

function normalizeState(state: Partial<TweakState>): TweakState {
	return {
		showDebugGrid: Boolean(state.showDebugGrid ?? DEFAULT_TWEAK_STATE.showDebugGrid),
		showDebugLayout: Boolean(state.showDebugLayout ?? DEFAULT_TWEAK_STATE.showDebugLayout),
		contentMaxWidth: clamp(
			Number(state.contentMaxWidth ?? DEFAULT_TWEAK_STATE.contentMaxWidth),
			640,
			1440
		),
		designOverlayImageUrl: DEFAULT_TWEAK_STATE.designOverlayImageUrl,
		designOverlayOpacity: DEFAULT_TWEAK_STATE.designOverlayOpacity
	};
}

export function loadTweakState(): TweakState {
	if (typeof window === 'undefined') return DEFAULT_TWEAK_STATE;

	const saved = localStorage.getItem(TWEAK_STORAGE_KEY);
	if (!saved) return DEFAULT_TWEAK_STATE;

	try {
		const parsed = JSON.parse(saved) as Partial<TweakState>;
		return normalizeState(parsed);
	} catch {
		return DEFAULT_TWEAK_STATE;
	}
}

export function saveTweakState(state: TweakState): void {
	if (typeof window === 'undefined') return;
	localStorage.setItem(TWEAK_STORAGE_KEY, JSON.stringify(normalizeState(state)));
}

export function applyTweakStateToDocument(state: TweakState): void {
	if (typeof document === 'undefined') return;

	const normalizedState = normalizeState(state);
	const root = document.documentElement;

	root.style.setProperty('--content-max-width', `${normalizedState.contentMaxWidth}px`);
}
