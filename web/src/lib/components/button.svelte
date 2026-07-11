<script lang="ts" module>
	import type { HTMLButtonAttributes, HTMLAnchorAttributes } from 'svelte/elements';
	export type ButtonVariant = 'default' | 'contained' | 'outlined';

	export type BaseProps = {
		variant?: ButtonVariant;
		size?: 'auto' | 'lg' | 'sm';
		color?: 'primary' | 'secondary' | 'success' | 'danger' | 'warning' | 'info';
		disabled?: boolean | null;
		pressed?: null;
		loading?: boolean;
	};

	export type PressableProps = Omit<BaseProps, 'variant' | 'pressed'> & {
		variant?: 'default';
		pressed: boolean;
	};

	export type AnchorProps = (PressableProps | BaseProps) &
		Omit<HTMLAnchorAttributes, 'aria-pressed' | 'aria-disabled' | 'class'>;
	export type ButtonProps = (PressableProps | BaseProps) &
		Omit<HTMLButtonAttributes, 'aria-pressed' | 'aria-disabled' | 'class'>;
</script>

<script lang="ts">
	let {
		children,
		variant = 'default',
		size = 'auto',
		disabled,
		pressed,
		color = 'primary',
		loading = false,
		...rest
	}: ButtonProps | AnchorProps = $props();

	let isAnchor = $derived('href' in rest);
	let pressable = $derived(pressed !== undefined && pressed !== null);
</script>

<svelte:element
	this={isAnchor ? 'a' : 'button'}
	{...rest}
	class={['button', variant, color, { disabled }, { pressable }]}
	class:small={size === 'sm'}
	class:large={size === 'lg'}
	disabled={isAnchor ? undefined : disabled || loading}
	aria-disabled={isAnchor ? disabled || loading : undefined}
	aria-pressed={pressed}
>
	{@render children?.()}
</svelte:element>

<style>
	.button {
		position: relative;
		text-decoration: none;
		cursor: pointer;
	}
</style>
