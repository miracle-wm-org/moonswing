# The Graceful Shell website

The project's website and wiki: <https://miracle-wm-org.github.io/graceful-shell/>

Built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build),
Astro's documentation theme. It is a static site — the build produces plain HTML with a
client-side search index, and nothing runs at request time.

## Running it locally

Node 20 or newer, then from this directory:

```sh
npm install
npm run dev          # http://localhost:4321/graceful-shell/
```

The dev server hot-reloads on every edit under `src/`, and on edits to `CONFIG.md` after a
`npm run sync` (see below).

Other scripts:

```sh
npm run build        # static site into dist/
npm run preview      # serve dist/ exactly as it will be deployed
npm run check        # type-check content collections, frontmatter and links
npm run sync         # regenerate the parts taken from the repository
```

## What is generated, and what is written by hand

`npm run sync` — which `npm run dev` and `npm run build` both run first — writes everything
the site takes from the repository itself, so no fact about Graceful Shell is maintained in
two places:

| Generated | From |
|---|---|
| `src/content/docs/configuration/*.md` | `../CONFIG.md`, split into pages |
| `public/favicon.svg`, `public/favicon.png` | `../assets/graceful-mark.svg` |
| `src/assets/graceful-agility.svg`, `public/og.png` | `../assets/graceful-agility.svg` |

All of it is gitignored. **Do not edit those files** — edit `CONFIG.md` or the SVGs in
`assets/` at the root of the repository, and re-run `npm run sync`.

Which `## ` sections of `CONFIG.md` land on which page is the `PAGES` table in
[`scripts/sync.mjs`](scripts/sync.mjs). Every heading must be claimed by exactly one page: a
new section that no page claims fails the build rather than quietly vanishing from the site.

Everything else — the landing page, `start/`, and `wiki/` — is hand-written Markdown under
`src/content/docs/`.

## Deploying

`.github/workflows/website.yml` builds this directory and publishes it to GitHub Pages on
every push to `main` that touches the site, `CONFIG.md` or `assets/`. It needs **Settings →
Pages → Source: GitHub Actions** enabled on the repository once.

The site is configured for a project page at `/graceful-shell/`. Moving it to a custom domain
is the two constants at the top of [`astro.config.mjs`](astro.config.mjs): set `site` to the
domain and `base` to `'/'`.
