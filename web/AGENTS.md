# Agent Guidelines

This document outlines the coding standards, architecture patterns, and conventions for this SvelteKit project. Follow these guidelines to maintain consistency.

---

## Project Structure

```
src/
├── lib/
│   ├── assets/          # Static assets (images, icons, fonts)
│   ├── components/      # Reusable Svelte components
│   └── modules/         # Feature modules
├── routes/              # SvelteKit routes
└── styles/
    ├── css/             # CSS files (reset.css, global.css)
    └── theme/           # Theme configuration (TypeScript)
        ├── colors.ts    # Color palette (light/dark)
        ├── variables.ts # Design tokens + Lightning CSS variables
        └── index.ts     # Barrel exports

vite-plugins/
└── lightningcss/        # Lightning CSS visitor plugins
    ├── px-to-rem.ts
    ├── environment-variables.ts
    └── index.ts
```

---

## Path Aliases

Always use path aliases instead of relative imports:

```typescript
// ✅ Good
import Button from '@components/button.svelte';
import { colors } from '@theme';

// ❌ Bad
import Button from '@components/Button.svelte';
import { colors } from '../../../styles/theme';
```

**Available aliases:**

- `@styles` → `./src/styles`
- `@theme` → `./src/styles/theme`
- `@components` → `./src/lib/components`
- `@assets` → `./src/lib/assets`
- `@modules` → `./src/lib/modules`
- `$lib` → `./src/lib` (SvelteKit default)

---

## Styling System

### Lightning CSS + Design Tokens

This project uses **Lightning CSS** with custom visitors for:

1. **px → rem conversion** - All `px` values automatically convert to `rem` (base: 16px)
2. **Environment variables** - TypeScript design tokens injected as `env()` variables

### Using Design Tokens

**In CSS:**

```css
.card {
	padding: env(--space-md); /* 16px → 1rem */
	background: env(--color-light-primary); /* #ffffff */
	box-shadow: env(--shadow-lg);
	transition: all env(--transition-base);
	font-family: env(--font-sans); /* Montserrat */
}

.code {
	font-family: env(--font-mono); /* SF Mono */
}

/* Light/Dark mode */
:root {
	--color-primary: light-dark(env(--color-light-primary), env(--color-dark-primary));
}
```

**In TypeScript/Svelte:**

```typescript
import { colors, Variables } from '@theme';

// Access colors
const primary = colors.light.primary; // '#ffffff'

// Access all variables
const spacing = Variables.space.md; // '16px'
```

### Adding New Design Tokens

Edit `src/styles/theme/variables.ts`:

```typescript
export const Variables = {
	color: {
		light: colors.light,
		dark: colors.dark
	},
	space: {
		xs: '4px',
		sm: '8px',
		md: '16px'
		// Add more...
	},
	// Add new categories...
	radius: {
		sm: '4px',
		md: '8px'
	}
};
```

Variables are automatically:

- Flattened: `space.md` → `env(--space-md)`
- Converted: `16px` → `1rem`
- Available in CSS via `env(--variable-name)`

---

## TypeScript Standards

### Strict Rules

- ✅ **No `any` type** - Use proper types or `unknown`
- ✅ **No unused variables** - Prefix with `_` if intentionally unused
- ✅ **Explicit types** for function parameters and return values
- ✅ **PascalCase** for types/interfaces/classes
- ✅ **camelCase** for variables/functions
- ✅ **UPPER_CASE** for constants

```typescript
// ✅ Good
interface UserProfile {
	name: string;
	age: number;
}

function getUserData(userId: string): Promise<UserProfile> {
	// implementation
}

const MAX_RETRIES = 3;

// ❌ Bad
function getData(id: any) {
	// No 'any'
	const unused = 5; // Unused variable
	return data; // No return type
}
```

---

## Import Ordering

Imports are automatically sorted by `eslint-plugin-simple-import-sort`:

```typescript
// 1. Node built-ins
import { resolve } from 'node:path';

// 2. SvelteKit
import { page } from '$app/stores';

// 3. External packages
import { writable } from 'svelte/store';

// 4. Aliases (in order)
import '@styles/css/global.css';
import { colors } from '@theme';
import Button from '@components/button.svelte';
import logo from '@assets/logo.svg';
import { auth } from '@modules/auth';

// 5. $lib
import { helper } from '$lib/utils';

// 6. Parent/sibling relative imports
import { local } from '../utils';
import { sibling } from './sibling';

// 7. Type imports (last)
import type { User } from '@modules/auth';
```

Run `pnpm format` to auto-fix import order.

---

## Svelte Component Standards

### Component Structure

```svelte
<script lang="ts">
	// 1. Imports (sorted)
	import { onMount } from 'svelte';
	import Button from '@components/Button.svelte';
	import type { User } from '@modules/auth';

	// 2. Props
	interface Props {
		user: User;
		onSave?: () => void;
	}

	let { user, onSave }: Props = $props();

	// 3. State
	let isLoading = $state(false);
	let count = $state(0);

	// 4. Derived state
	let displayName = $derived(user.name.toUpperCase());

	// 5. Functions
	function handleClick() {
		count++;
		onSave?.();
	}

	// 6. Lifecycle
	onMount(() => {
		// initialization
	});
</script>

<!-- Template -->
<div class="container">
	<Button onclick={handleClick}>
		{displayName}
	</Button>
</div>

<!-- Scoped styles -->
<style>
	.container {
		padding: env(--space-md);
		background: env(--color-light-primary);
	}
</style>
```

### Svelte 5 Runes

Use Svelte 5 runes syntax:

```typescript
// ✅ Good (Svelte 5)
let count = $state(0);
let doubled = $derived(count * 2);
let { user } = $props();

// ❌ Bad (Svelte 4)
let count = 0;
$: doubled = count * 2;
export let user;
```

---

## File Naming Conventions

**ALL files must use `kebab-case`:**

- **Components**: `kebab-case.svelte` (e.g., `button.svelte`, `user-profile.svelte`)
- **Routes**: `kebab-case` (e.g., `+page.svelte`, `user-profile/+page.svelte`)
- **TypeScript**: `kebab-case.ts` (e.g., `auth-service.ts`, `user-types.ts`)
- **CSS**: `kebab-case.css` (e.g., `global.css`, `reset.css`)

```
✅ Good:
- button.svelte
- user-profile.svelte
- auth-service.ts
- api-client.ts

❌ Bad:
- Button.svelte (PascalCase)
- UserProfile.svelte (PascalCase)
- authService.ts (camelCase)
- APIClient.ts (PascalCase)
```

---

## ESLint & Prettier

### Running Checks

```bash
pnpm lint          # Check for errors
pnpm format        # Auto-fix formatting
pnpm check         # TypeScript + Svelte check
```

### Key Rules

- Import sorting (auto-fixed)
- No unused variables
- No `any` type
- Svelte best practices (shorthand attributes, class directives)
- Naming conventions enforced

---

## Lightning CSS Configuration

### Adding Custom Visitors

Create visitors in `vite-plugins/lightningcss/`:

```typescript
import type { CustomAtRules, Visitor } from 'lightningcss';

export function myVisitor(): Visitor<CustomAtRules> {
	return {
		Length(length) {
			// Transform length values
			return length;
		}
	};
}
```

Register in `vite.config.ts`:

```typescript
import { composeVisitors } from 'lightningcss';
import { pxToRem, environmentVariables, myVisitor } from './vite-plugins/lightningcss';

visitor: composeVisitors([
	pxToRem(),
	environmentVariables({ variables: Variables, breakpoints: Breakpoints }),
	myVisitor()
]);
```

---

## Best Practices

### 1. Minimal Code

Write the **absolute minimum** code needed. Avoid verbose implementations.

```typescript
// ✅ Good
const active = status === 'active';

// ❌ Bad
let active: boolean;
if (status === 'active') {
	active = true;
} else {
	active = false;
}
```

### 2. Type Safety

Always provide types, never use `any`.

```typescript
// ✅ Good
function process(data: User[]): string[] {
	return data.map((u) => u.name);
}

// ❌ Bad
function process(data: any) {
	return data.map((u: any) => u.name);
}
```

### 3. Use Aliases

Never use relative imports when aliases are available.

### 4. Design Tokens

Use `env()` variables in CSS, never hardcode values.

```css
/* ✅ Good */
.card {
	padding: env(--space-md);
	color: env(--color-light-primary);
}

/* ❌ Bad */
.card {
	padding: 16px;
	color: #ffffff;
}
```

### 5. Component Composition

Keep components small and focused. Extract reusable logic.

---

## Common Patterns

### Creating a New Component

1. Create file: `src/lib/components/my-component.svelte` (kebab-case)
2. Use TypeScript for props
3. Use design tokens for styling
4. Export from component if needed

```svelte
<script lang="ts">
	interface Props {
		title: string;
		variant?: 'primary' | 'secondary';
	}

	let { title, variant = 'primary' }: Props = $props();
</script>

<button class="btn {variant}">
	{title}
</button>

<style>
	.btn {
		padding: env(--space-sm) env(--space-md);
		transition: all env(--transition-fast);
	}

	.primary {
		background: env(--color-light-primary);
	}
</style>
```

### Adding a New Route

1. Create `src/routes/my-route/+page.svelte`
2. Optional: `+page.ts` for data loading
3. Use layout for shared styles

---

## Questions?

When in doubt:

1. Check existing code for patterns
2. Follow TypeScript strict mode
3. Use design tokens via `env()`
4. Use path aliases
5. Keep it minimal

---

**Last Updated**: 2026-02-24
