export const colors = {
	light: {
		primary: '#ffffff',
		secondary: '#f8f9fa',
		tertiary: '#e9ecef',
		accent: '#dee2e6'
	},
	dark: {
		primary: '#212529',
		secondary: '#343a40',
		tertiary: '#495057',
		accent: '#6c757d'
	}
} as const;

export type ColorScheme = keyof typeof colors;
export type ColorKey = keyof typeof colors.light;
