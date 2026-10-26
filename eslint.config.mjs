// JavaScript and TypeScript are linted with no-unused-vars (docs/dev/lint.md); tools/lint/tool.sh runs the eslint
// whose installation holds the TypeScript parser.
import { createRequire } from 'node:module';

const tseslint = createRequire(process.argv[1])('typescript-eslint');

export default [
  { ignores: ['**/node_modules/**', '**/gen/**', '**/build/**'] },
  { files: ['**/*.{js,mjs}'], rules: { 'no-unused-vars': 'error' } },
  {
    files: ['**/*.ts'],
    languageOptions: { parser: tseslint.parser },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules: { '@typescript-eslint/no-unused-vars': 'error' },
  },
];
