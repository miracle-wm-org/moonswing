// Generates everything the site takes from the repository itself, so no fact
// about Graceful Shell is maintained twice:
//
//   ../CONFIG.md            -> src/content/docs/configuration/*.md
//   ../assets/*.svg         -> public/ and src/assets/ (favicon, hero, card)
//
// Both outputs are gitignored. `npm run dev` and `npm run build` run this
// first, so a CONFIG.md edit is live on the next dev-server reload and lands
// on the site with the commit that made it.

import { mkdir, readFile, rm, writeFile, copyFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, '..');
const repo = join(site, '..');

const outDir = join(site, 'src/content/docs/configuration');
const publicDir = join(site, 'public');
const assetDir = join(site, 'src/assets');

/**
 * The configuration reference, page by page.
 *
 * `sections` names `## ` headings of CONFIG.md verbatim; a page may pull
 * several, and they are emitted in the order listed here rather than the order
 * they appear in the file. Every heading in CONFIG.md must be claimed by
 * exactly one page — the script fails the build otherwise, so a new `##`
 * section cannot be silently dropped from the site.
 */
const PAGES = [
  {
    slug: 'panels',
    title: 'Panels and layout',
    description: 'Panel geometry, anchors, layers, and which modules sit where.',
    sections: ['Panels', 'Layout'],
  },
  {
    slug: 'modules',
    title: 'Modules',
    description: 'Per-module options for every `[modules.*]` strip on the bar.',
    sections: ['Module Settings'],
  },
  {
    slug: 'shortcuts',
    title: 'Shortcuts',
    description: 'Key bindings the shell asks the compositor to route to it.',
    sections: ['Shortcuts'],
  },
  {
    slug: 'theme',
    title: 'Theme',
    description: 'Palette, fonts, panel and popup geometry.',
    sections: ['Theme'],
  },
  {
    slug: 'background',
    title: 'Background',
    description: 'Wallpaper sources, fit, and rotation.',
    sections: ['Background'],
  },
  {
    slug: 'desktop',
    title: 'Desktop icons and widgets',
    description: 'The desktop grid: icons, and the widgets that share it.',
    sections: ['Desktop Icons', 'Desktop Widgets'],
  },
  {
    slug: 'lock-screen',
    title: 'Lock screen',
    description: 'Idle locking, the lock wallpaper, and what it needs installed.',
    sections: ['Lock Screen'],
  },
  {
    slug: 'overlays',
    title: 'Overlays and system integration',
    description:
      'The emoji picker, calendar, on-screen indicator, power button, ' +
      'authentication prompts and screen sharing.',
    sections: [
      'Emoji Picker',
      'Calendar',
      'On-Screen Indicator',
      'Power Button',
      'Authentication Prompts',
      'Screen Sharing',
    ],
  },
  {
    slug: 'full-example',
    title: 'Full example',
    description: 'One config.toml exercising every section.',
    sections: ['Full Example'],
  },
];

/** Splits a markdown document into `{ title, body }` records, one per `## `. */
function splitSections(markdown) {
  const lines = markdown.split('\n');
  const preamble = [];
  const sections = [];
  let current = null;
  let inFence = false;

  for (const line of lines) {
    // A `## ` inside a fenced block is TOML/shell content, not a heading.
    if (/^\s*```/.test(line)) inFence = !inFence;

    const heading = !inFence && /^## (?!#)(.+)$/.exec(line);
    if (heading) {
      current = { title: heading[1].trim(), body: [] };
      sections.push(current);
      continue;
    }
    (current ? current.body : preamble).push(line);
  }

  return {
    preamble: preamble.join('\n').trim(),
    sections: sections.map((s) => ({ title: s.title, body: s.body.join('\n').trim() })),
  };
}

/** `## ` becomes the page title, so everything below it shifts up one level. */
function promoteHeadings(body) {
  let inFence = false;
  return body
    .split('\n')
    .map((line) => {
      if (/^\s*```/.test(line)) inFence = !inFence;
      if (inFence) return line;
      return line.replace(/^(#{3,6}) /, (_, hashes) => `${hashes.slice(1)} `);
    })
    .join('\n');
}

/** YAML needs quoting for a description that may contain a colon or a quote. */
function yamlString(value) {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

async function generateConfigPages() {
  const source = await readFile(join(repo, 'CONFIG.md'), 'utf8');
  const { preamble, sections } = splitSections(source);
  // The document's `# ` title is the page title of the index; keeping it would
  // print it twice.
  const intro = preamble.replace(/^# .*\n+/, '');
  const byTitle = new Map(sections.map((s) => [s.title, s]));

  const claimed = new Set();
  for (const page of PAGES) {
    for (const title of page.sections) {
      if (!byTitle.has(title)) {
        throw new Error(
          `CONFIG.md has no "## ${title}" section (wanted by configuration/${page.slug}). ` +
            `Update PAGES in website/scripts/sync.mjs.`,
        );
      }
      if (claimed.has(title)) throw new Error(`"## ${title}" is claimed by two pages.`);
      claimed.add(title);
    }
  }

  const orphans = sections.map((s) => s.title).filter((t) => !claimed.has(t));
  if (orphans.length > 0) {
    throw new Error(
      `CONFIG.md sections not on any page: ${orphans.map((t) => `"${t}"`).join(', ')}. ` +
        `Add them to PAGES in website/scripts/sync.mjs.`,
    );
  }

  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });

  const banner = (order) =>
    [
      '---',
      'title: ' + yamlString(order.title),
      'description: ' + yamlString(order.description),
      `sidebar:\n  order: ${order.order}` + (order.label ? `\n  label: ${yamlString(order.label)}` : ''),
      'editUrl: https://github.com/miracle-wm-org/graceful-shell/edit/main/CONFIG.md',
      '---',
      '',
      '<!-- Generated from CONFIG.md by website/scripts/sync.mjs — do not edit. -->',
      '',
    ].join('\n');

  await writeFile(
    join(outDir, 'index.md'),
    banner({
      title: 'Configuration',
      description:
        'Where the config file lives, how it degrades, and what every section holds.',
      order: 0,
      // The group in the sidebar is already called Configuration.
      label: 'Overview',
    }) +
      `${intro}\n\n## In this section\n\n` +
      PAGES.map((p) => `- [${p.title}](/configuration/${p.slug}/) — ${p.description}`).join('\n') +
      '\n',
    'utf8',
  );

  for (const [index, page] of PAGES.entries()) {
    // A page built from one section drops the redundant heading and promotes
    // what was under it; a page built from several keeps each heading, and so
    // must leave the levels below it alone.
    const single = page.sections.length === 1;
    const body = page.sections
      .map((title) => {
        const section = byTitle.get(title);
        return single
          ? promoteHeadings(section.body)
          : `## ${section.title}\n\n${section.body}`;
      })
      .join('\n\n');

    await writeFile(
      join(outDir, `${page.slug}.md`),
      banner({ ...page, order: index + 1 }) + body + '\n',
      'utf8',
    );
  }

  return PAGES.length + 1;
}

async function generateArtwork() {
  await mkdir(publicDir, { recursive: true });
  await mkdir(assetDir, { recursive: true });

  const mark = join(repo, 'assets/graceful-mark.svg');
  const hero = join(repo, 'assets/graceful-agility.svg');

  await copyFile(mark, join(publicDir, 'favicon.svg'));
  // The hero goes through Astro's asset pipeline, which only reaches src/.
  await copyFile(hero, join(assetDir, 'graceful-agility.svg'));

  // A raster fallback for browsers with no SVG favicon support, and a social
  // card, which no platform will render from SVG. Both are pixel art, so both
  // are integer multiples of the source — 192 is 6x the 32px sprite, 1920x840
  // is 2x the banner — and both resample nearest-neighbour. Anything else
  // resamples the sprite into mush.
  await sharp(mark, { density: 1200 })
    .resize(192, 192, { kernel: 'nearest' })
    .png()
    .toFile(join(publicDir, 'favicon.png'));
  await sharp(hero, { density: 300 })
    .resize(1920, 840, { kernel: 'nearest' })
    .png()
    .toFile(join(publicDir, 'og.png'));
}

const pages = await generateConfigPages();
await generateArtwork();
console.log(`sync: ${pages} configuration pages from CONFIG.md, artwork from assets/`);
