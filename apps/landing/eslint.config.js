import js from '@eslint/js';
import globals from 'globals';
import vue from 'eslint-plugin-vue';
import prettier from 'eslint-config-prettier';

/**
 * The landing site's lint (OPH-274).
 *
 * The `lint` script has existed since this workspace did, and it has never run:
 * there was no flat config, so eslint 9 exited with "couldn't find a
 * configuration file" — and CI never called it, so nothing said so. The repo
 * believed it linted three apps and linted two.
 *
 * Deliberately close to `apps/api/eslint.config.js` rather than its own
 * dialect: one house style, two runtimes. The differences are exactly the two
 * things that ARE different here — the browser globals, and `.vue` files.
 */
export default [
  { ignores: ['node_modules/**', 'dist/**', 'public/shots/**'] },
  js.configs.recommended,
  ...vue.configs['flat/recommended'],
  {
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      // Vite config and the build scripts are Node; the site is the browser.
      globals: { ...globals.browser, ...globals.node },
    },
    rules: {
      'no-var': 'error',
      'prefer-const': 'error',
      eqeqeq: ['error', 'smart'],
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      // The build scripts report progress on stdout; that is their job.
      'no-console': 'off',
    },
  },
  prettier,
];
