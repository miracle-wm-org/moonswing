// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// GitHub Pages serves a project site under /<repo>/. Publishing to a custom
// domain instead means setting `site` to it and dropping `base` — those two
// lines are the whole difference.
const site = 'https://miracle-wm-org.github.io';
const base = '/graceful-shell';

const repo = 'https://github.com/miracle-wm-org/graceful-shell';

export default defineConfig({
  site,
  base,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'Graceful Shell',
      description:
        'A Flutter desktop shell for Wayland: panels, wallpaper, desktop icons, ' +
        'overlays, notifications, tray, screen sharing and a lock screen.',
      logo: { src: './public/favicon.svg', alt: 'Graceful Shell' },
      favicon: '/favicon.svg',
      head: [
        // SVG favicons are near-universal now, but a raster fallback costs one
        // link tag and covers what is left.
        {
          tag: 'link',
          attrs: { rel: 'icon', href: `${base}/favicon.png`, type: 'image/png', sizes: '192x192' },
        },
        {
          tag: 'link',
          attrs: { rel: 'apple-touch-icon', href: `${base}/favicon.png`, sizes: '192x192' },
        },
        // No platform renders an SVG social card, so this one is rasterised by
        // `npm run sync`.
        { tag: 'meta', attrs: { property: 'og:image', content: `${site}${base}/og.png` } },
        { tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
        { tag: 'meta', attrs: { name: 'theme-color', content: '#1b0711' } },
      ],
      social: [{ icon: 'github', label: 'GitHub', href: repo }],
      editLink: { baseUrl: `${repo}/edit/main/website/` },
      lastUpdated: true,
      customCss: ['./src/styles/graceful.css'],
      sidebar: [
        { label: 'Getting started', items: [{ autogenerate: { directory: 'start' } }] },
        { label: 'Configuration', items: [{ autogenerate: { directory: 'configuration' } }] },
        { label: 'Wiki', items: [{ autogenerate: { directory: 'wiki' } }] },
      ],
      credits: false,
    }),
  ],
});
