/// <reference types="vitest/config" />
import {defineConfig} from 'vitest/config';
import react from '@vitejs/plugin-react';

// Phoenix's PageController serves priv/static/index.html and replaces the
// literal `__SERVER_ENV_DATA__` token with a JSON blob at request time, which
// the app reads as `window.__ENV__` (see src/config.ts). CRA did this via an
// EJS `<% if production %>` guard in public/index.html; Vite has no EJS, so we
// inject the runtime-env <script> only into the *production* build output and
// leave it out of the dev server (where window.__ENV__ stays undefined and
// config.ts falls back to defaults).
const serverEnvHtmlPlugin = () => ({
  name: 'papercups-inject-server-env',
  transformIndexHtml: {
    order: 'post' as const,
    handler(html: string, ctx: {server?: unknown}) {
      if (ctx.server) {
        return html; // dev server: no injection
      }

      return html.replace(
        '</head>',
        '  <script>window.__ENV__ = __SERVER_ENV_DATA__;</script>\n  </head>'
      );
    },
  },
});

export default defineConfig({
  plugins: [react(), serverEnvHtmlPlugin()],
  build: {
    // Keep the CRA output dir name so the `postbuild` copy to ../priv/static
    // and the Dockerfile/phx.digest steps stay unchanged.
    outDir: 'build',
    sourcemap: false,
  },
  server: {
    port: 3000,
    // Replaces CRA's `"proxy": "http://localhost:4000"`: proxy the API and the
    // Phoenix channel socket to the backend during development.
    proxy: {
      '/api': 'http://localhost:4000',
      '/socket': {target: 'ws://localhost:4000', ws: true},
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/setupTests.ts',
    css: false,
  },
});
