import { colors } from './colors';

export const Variables = {
	color: {
		light: colors.light,
		dark: colors.dark
	},
	space: {
		xs: '4rem',
		sm: '8rem',
		md: '16rem',
		lg: '24rem',
		xl: '32rem',
		xxl: '48rem'
	},
	shadow: {
		sm: '0 1px 2px 0 rgb(0 0 0 / 0.05)',
		md: '0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -1px rgb(0 0 0 / 0.06)',
		lg: '0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -2px rgb(0 0 0 / 0.05)',
		xl: '0 20px 25px -5px rgb(0 0 0 / 0.1), 0 10px 10px -5px rgb(0 0 0 / 0.04)'
	},
	transition: {
		fast: '150ms ease',
		base: '250ms ease',
		slow: '350ms ease'
	},
	font: {
		sans: "'Montserrat', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
		mono: "'SF Mono', Monaco, 'Cascadia Code', 'Courier New', monospace"
	},
	grid: {
		'columns-mobile': '3',
		'columns-tablet': '8',
		'columns-desktop': '12',
		'gap-mobile': '8px',
		'gap-tablet': '12px',
		'gap-desktop': '20px'
	}
} as const;

export const Breakpoints = {
	tn: '(min-width: 320px)',
	sm: '(min-width: 430px)',
	md: '(min-width: 570px)',
	lg: '(min-width: 760px)',
	xl: '(min-width: 1080px)',
	'2xl': '(min-width: 1600px)',
	'3xl': '(min-width: 2400px)',
	landscape: '(orientation: landscape)'
} as const;

export const BreakpointsPx = {
	tn: 320,
	sm: 430,
	md: 570,
	lg: 760,
	xl: 1080,
	'2xl': 1600,
	'3xl': 2400
} as const;

export type Breakpoint = keyof typeof Breakpoints;
export type BreakpointValue = (typeof Breakpoints)[Breakpoint];
