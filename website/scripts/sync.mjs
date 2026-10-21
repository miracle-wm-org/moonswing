// Generates everything the site takes from the repository itself, so no fact
// about Moonswing is maintained twice:
//
//   ../CONFIG.md            -> src/content/docs/configuration/ (see pages.mjs)
//   ../assets/*.svg         -> public/ and src/assets/ (favicon, hero, card)
//
// Both outputs are gitignored. `npm run dev` and `npm run build` run this
// first, so a CONFIG.md edit is live on the next dev-server reload and lands
// on the site with the commit that made it.

import { mkdir, readFile, rm, writeFile, copyFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

import { PAGES } from './pages.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, '..');
const repo = join(site, '..');

const outDir = join(site, 'src/content/docs/configuration');
const publicDir = join(site, 'public');
const assetDir = join(site, 'src/assets');

/**
 * The anchor GitHub's renderer — and Astro's, which uses the same slugger —
 * gives a heading: deduplicated within one document, which for Astro is one
 * page.
 */
class Slugger {
  #seen = new Map();

  slug(heading) {
    const text = heading.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/[`*]/g, '');
    const base = text
      .toLowerCase()
      .replace(/[^\p{L}\p{M}\p{N}\p{Pc}\- ]/gu, '')
      .replace(/ /g, '-');
    let slug = base;
    while (this.#seen.has(slug)) {
      const n = this.#seen.get(base) + 1;
      this.#seen.set(base, n);
      slug = `${base}-${n}`;
    }
    this.#seen.set(slug, 0);
    return slug;
  }
}

/**
 * CONFIG.md as line records. A heading carries its `level`, its `title` and
 * the `anchor` it has on GitHub, so a link to it can still be found once the
 * file is split into pages; a line in a fenced block is `fenced`, since a `#`
 * there is TOML or shell, not a heading.
 */
function readLines(markdown) {
  const slugger = new Slugger();
  let inFence = false;
  return markdown.split('\n').map((text) => {
    if (/^\s*```/.test(text)) {
      inFence = !inFence;
      return { text, fenced: true };
    }
    if (inFence) return { text, fenced: true };
    const heading = /^(#{1,6}) (.+)$/.exec(text);
    if (!heading) return { text };
    const title = heading[2].trim();
    return { text, level: heading[1].length, title, anchor: slugger.slug(title) };
  });
}

/** Splits line records at every heading of `level` into `{ heading, lines }`. */
function splitAt(lines, level) {
  const preamble = [];
  const sections = [];
  for (const line of lines) {
    if (line.level === level) {
      sections.push({ heading: line, lines: [] });
    } else {
      (sections.at(-1)?.lines ?? preamble).push(line);
    }
  }
  return { preamble: trim(preamble), sections: sections.map((s) => ({ ...s, lines: trim(s.lines) })) };
}

/** Drops blank lines from either end. */
function trim(lines) {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start].text.trim() === '') start++;
  while (end > start && lines[end - 1].text.trim() === '') end--;
  return lines.slice(start, end);
}

/** Moves every heading up `by` levels — what was under the page title now sits under `# `. */
function promote(lines, by) {
  return lines.map((line) => (line.level ? { ...line, level: line.level - by } : line));
}

const text = (value) => ({ text: value });
const heading = (level, title) => ({ level, title });

/** YAML needs quoting for a description that may contain a colon or a quote. */
function yamlString(value) {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function banner({ title, description, order, label }) {
  return [
    '---',
    'title: ' + yamlString(title),
    'description: ' + yamlString(description),
    `sidebar:\n  order: ${order}` + (label ? `\n  label: ${yamlString(label)}` : ''),
    'editUrl: https://github.com/miracle-wm-org/moonswing/edit/main/CONFIG.md',
    '---',
    '',
    '<!-- Generated from CONFIG.md by website/scripts/sync.mjs — do not edit. -->',
    '',
  ].join('\n');
}

async function generateConfigPages() {
  const lines = readLines(await readFile(join(repo, 'CONFIG.md'), 'utf8'));
  const { preamble, sections } = splitAt(lines, 2);
  const byTitle = new Map(sections.map((s) => [s.heading.title, s]));

  const claimed = new Set();
  for (const page of PAGES) {
    for (const title of page.sections) {
      if (!byTitle.has(title)) {
        throw new Error(
          `CONFIG.md has no "## ${title}" section (wanted by configuration/${page.slug}). ` +
            `Update PAGES in website/scripts/pages.mjs.`,
        );
      }
      if (claimed.has(title)) throw new Error(`"## ${title}" is claimed by two pages.`);
      claimed.add(title);
    }
    if (page.split && page.sections.length !== 1) {
      throw new Error(`configuration/${page.slug} is split, so it takes exactly one section.`);
    }
  }

  const orphans = sections.map((s) => s.heading.title).filter((t) => !claimed.has(t));
  if (orphans.length > 0) {
    throw new Error(
      `CONFIG.md sections not on any page: ${orphans.map((t) => `"${t}"`).join(', ')}. ` +
        `Add them to PAGES in website/scripts/pages.mjs.`,
    );
  }

  // Every page to write: where it goes, its frontmatter, the headings whose
  // anchor is now the page itself (they became its title), and its lines.
  const pages = [];
  const listing = [];

  for (const [index, page] of PAGES.entries()) {
    const url = `/configuration/${page.slug}/`;
    const order = index + 1;

    if (page.split) {
      const section = byTitle.get(page.sections[0]);
      const { preamble: intro, sections: parts } = splitAt(section.lines, 3);
      const slugger = new Slugger();
      const children = parts.map((part, i) => {
        const slug = slugger.slug(part.heading.title);
        return {
          path: `${page.slug}/${slug}.md`,
          url: `${url}${slug}/`,
          title: part.heading.title,
          description: page.split.describe(
            part.heading.title,
            part.lines.map((l) => l.text).join('\n'),
          ),
          order: i + 1,
          titled: [part.heading],
          // `### ` was the page title, so `#### ` is now `## `.
          lines: promote(part.lines, 2),
        };
      });
      const childList = children.map((c) => text(`- [${c.title}](${c.url})`));
      pages.push(
        {
          path: `${page.slug}/index.md`,
          url,
          title: page.title,
          description: page.description,
          order: 0,
          // The group in the sidebar is already called by the page's title.
          label: 'Overview',
          titled: [section.heading],
          lines: [...intro, text(''), heading(2, 'In this section'), text(''), ...childList],
        },
        ...children,
      );
      listing.push(
        text(`- [${page.title}](${url}) — ${page.description}`),
        ...children.map((c) => text(`  - [${c.title}](${c.url})`)),
      );
      continue;
    }

    // A page built from one section drops the redundant heading and promotes
    // what was under it; a page built from several keeps each heading, and so
    // must leave the levels below it alone.
    const parts = page.sections.map((title) => byTitle.get(title));
    const single = parts.length === 1;
    pages.push({
      path: `${page.slug}.md`,
      url,
      title: page.title,
      description: page.description,
      order,
      titled: single ? [parts[0].heading] : [],
      lines: single
        ? promote(parts[0].lines, 1)
        : parts.flatMap((part, i) => [
            ...(i > 0 ? [text('')] : []),
            part.heading,
            text(''),
            ...part.lines,
          ]),
    });
    listing.push(text(`- [${page.title}](${url}) — ${page.description}`));
  }

  // The document's `# ` title is the page title of the index; keeping it would
  // print it twice.
  const [title, ...intro] = preamble;
  pages.unshift({
    path: 'index.md',
    url: '/configuration/',
    title: 'Configuration',
    description:
      'Where the config file lives, how it degrades, and what every section holds.',
    order: 0,
    // The group in the sidebar is already called Configuration.
    label: 'Overview',
    titled: title.level === 1 ? [title] : [],
    lines: [
      ...(title.level === 1 ? trim(intro) : preamble),
      text(''),
      heading(2, 'In this section'),
      text(''),
      ...listing,
    ],
  });

  // Where each of CONFIG.md's anchors ended up. Links within the file are
  // written as `#anchor`, which only resolves on the page holding it.
  const anchors = new Map();
  for (const page of pages) {
    for (const line of page.titled) anchors.set(line.anchor, { page, hash: '' });
    const slugger = new Slugger();
    for (const line of page.lines) {
      if (!line.level) continue;
      const local = slugger.slug(line.title);
      if (line.anchor) anchors.set(line.anchor, { page, hash: `#${local}` });
    }
  }

  const unresolved = new Set();
  const render = (page, line) => {
    if (line.level) return `${'#'.repeat(line.level)} ${line.title}`;
    if (line.fenced) return line.text;
    return line.text.replace(/\]\(#([^)\s]+)\)/g, (match, anchor) => {
      const target = anchors.get(anchor);
      if (!target) {
        unresolved.add(anchor);
        return match;
      }
      if (target.page === page) return `](${target.hash || '#_top'})`;
      return `](${target.page.url}${target.hash})`;
    });
  };

  await rm(outDir, { recursive: true, force: true });
  for (const page of pages) {
    const file = join(outDir, page.path);
    await mkdir(dirname(file), { recursive: true });
    const body = page.lines.map((line) => render(page, line)).join('\n');
    await writeFile(file, banner(page) + body + '\n', 'utf8');
  }

  if (unresolved.size > 0) {
    console.warn(
      `sync: CONFIG.md links to anchors it has no heading for: ` +
        [...unresolved].map((a) => `#${a}`).join(', '),
    );
  }

  return pages.length;
}

async function generateArtwork() {
  await mkdir(publicDir, { recursive: true });
  await mkdir(assetDir, { recursive: true });

  const mark = join(repo, 'assets/moonswing-mark.svg');
  const hero = join(repo, 'assets/moonswing-banner.svg');

  await copyFile(mark, join(publicDir, 'favicon.svg'));
  // The hero goes through Astro's asset pipeline, which only reaches src/.
  await copyFile(hero, join(assetDir, 'moonswing-banner.svg'));

  // A raster fallback for browsers with no SVG favicon support, and a social
  // card, which no platform will render from SVG. The artwork is smooth vector
  // — curves and a gradient, not a pixel grid — so both render at several
  // times the target and come down with the default filter. The nearest
  // neighbour these used while the mark was pixel art would now alias every
  // rope and the moon's limb.
  await sharp(mark, { density: 2400 })
    .resize(192, 192)
    .png()
    .toFile(join(publicDir, 'favicon.png'));
  await sharp(hero, { density: 288 })
    .resize(1920, 840)
    .png()
    .toFile(join(publicDir, 'og.png'));
}

const pages = await generateConfigPages();
await generateArtwork();
console.log(`sync: ${pages} configuration pages from CONFIG.md, artwork from assets/`);
