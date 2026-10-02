import test from 'node:test';
import assert from 'node:assert/strict';
import story from '../data/story.json' with { type: 'json' };

// These tests guard data/story.json against values that scripts/main.js cannot render
// correctly or safely. Each rule targets how a field is actually used: most strings are
// interpolated into innerHTML, some into attributes, a few are set with textContent.
// A rule only applies where the renderer needs it, so legitimate content still passes.
// These are data checks; they do not render the page.

// The HTML parser acts on tag and comment openers and on character references.
// Plain prose such as "R&D", "AT&T" or "<10 users" is left alone by the parser, so it stays legal.
const MARKUP_OPENER = /<[a-z!/?]/i;
const CHARACTER_REFERENCE = /&(?:#\d+;?|#x[0-9a-f]+;?|[a-z][a-z0-9]*;|(?:amp|lt|gt|quot|nbsp|copy|reg)(?![a-z0-9]))/i;

function assertText(value, label) {
  assert.equal(typeof value, 'string', `${label} must be a string`);
  assert.ok(value.trim(), `${label} must not be empty`);
}

// For strings the renderer writes with innerHTML.
function assertMarkupSafeText(value, label) {
  assertText(value, label);
  assert.ok(!MARKUP_OPENER.test(value), `${label} must not contain HTML markup: ${value}`);
  assert.ok(
    !CHARACTER_REFERENCE.test(value),
    `${label} must not contain an HTML character reference, which the page would decode: ${value}`
  );
}

function assertArray(value, label, minimum = 1) {
  assert.ok(Array.isArray(value), `${label} must be an array`);
  assert.ok(value.length >= minimum, `${label} must include at least ${minimum} entr${minimum === 1 ? 'y' : 'ies'}`);
}

function assertRatio(value, label) {
  assert.equal(typeof value, 'number', `${label} must be a number`);
  assert.ok(Number.isFinite(value), `${label} must be finite`);
  assert.ok(value >= 0 && value <= 1, `${label} must fall between 0 and 1, received ${value}`);
}

const LINK_SCHEMES = new Set(['http:', 'https:', 'mailto:']);

// Written into href="...": anything that could leave the attribute is rejected, and only
// schemes that navigate somewhere ordinary are allowed. Relative paths are fine.
function assertLink(value, label) {
  assertText(value, label);
  assert.ok(!/["'<>\s]/.test(value), `${label} must not contain quotes, angle brackets or whitespace: ${value}`);

  let url;
  try {
    url = new URL(value, 'https://relative-link.invalid/');
  } catch {
    assert.fail(`${label} is not a valid URL: ${value}`);
  }
  assert.ok(LINK_SCHEMES.has(url.protocol), `${label} must be http(s), mailto, or a relative path, not ${url.protocol}`);
  if (url.protocol !== 'mailto:') {
    assert.ok(url.hostname, `${label} must include a host: ${value}`);
  }
}

// Written into style="background-image: ...", so it must be an image value. A plain
// colour is not a valid background-image and renders nothing.
const CSS_IMAGE = /^(?:(?:repeating-)?(?:linear|radial|conic)-gradient|url)\(.+\)$/i;

function assertBackgroundImage(value, label) {
  assertText(value, label);
  assert.ok(
    CSS_IMAGE.test(value.trim()),
    `${label} must be a CSS gradient or url(...), because it is rendered as background-image (a plain colour shows nothing): ${value}`
  );
  assert.ok(!/["<>;]/.test(value), `${label} must not contain quotes, angle brackets or semicolons: ${value}`);
}

test('profile provides the headline copy', () => {
  // Rendered with textContent.
  assertText(story.profile?.name, 'Profile name');
  assertText(story.profile?.tagline, 'Profile tagline');
  assertText(story.profile?.summary, 'Profile summary');
});

test('profile stats carry a label and a displayable value', () => {
  // An empty list renders a hero without stats, which is legitimate.
  assertArray(story.profile?.stats, 'Profile stats', 0);

  for (const [index, stat] of story.profile.stats.entries()) {
    assertMarkupSafeText(stat?.label, `Stat ${index} label`);

    // formatStatValue abbreviates numbers and passes strings such as "1.2M" through as-is.
    if (typeof stat?.value === 'string') {
      assertMarkupSafeText(stat.value, `Stat ${index} value`);
    } else {
      assert.equal(typeof stat?.value, 'number', `Stat ${index} value must be a number or a string`);
      assert.ok(Number.isFinite(stat.value), `Stat ${index} value must be finite`);
    }
  }
});

test('profile includes prompts and focus areas', () => {
  // Rendered with textContent.
  assertArray(story.profile?.prompts, 'Prompts', 3);
  assertArray(story.profile?.focus, 'Focus');

  story.profile.prompts.forEach((prompt, index) => assertText(prompt, `Prompt ${index}`));
  story.profile.focus.forEach((item, index) => assertText(item, `Focus area ${index}`));
});

test('signals track cadence and a 0-1 metric', () => {
  assertArray(story.signals, 'Signals');

  for (const [index, signal] of story.signals.entries()) {
    assertMarkupSafeText(signal?.title, `Signal ${index} title`);
    assertMarkupSafeText(signal?.cadence, `Signal ${index} cadence`);
    assertMarkupSafeText(signal?.description, `Signal ${index} description`);
    assertRatio(signal?.metric, `Signal ${index} metric`);
  }
});

test('timeline entries include a sortable year and essential fields', () => {
  assertArray(story.timeline, 'Timeline', 3);

  for (const [index, entry] of story.timeline.entries()) {
    // renderTimeline sorts with (a, b) => a.year - b.year. A year that does not coerce to
    // a number (for example "2014-2016") makes the comparator return NaN and leaves the
    // timeline unordered. Integer years and integer strings both sort correctly.
    const year = entry?.year;
    assert.ok(
      (typeof year === 'number' && Number.isInteger(year)) || (typeof year === 'string' && /^-?\d+$/.test(year)),
      `Timeline entry ${index} year must be an integer or a string of digits, received ${JSON.stringify(year)}`
    );
    assertMarkupSafeText(entry?.title, `Timeline entry ${index} title`);
    assertMarkupSafeText(entry?.description, `Timeline entry ${index} description`);
    assertMarkupSafeText(entry?.category, `Timeline entry ${index} category`);
    // index.html already has an "All" chip for every entry, so a category of any
    // casing of "all" would add a second chip with the same label.
    assert.notEqual(
      entry.category.trim().toLowerCase(),
      'all',
      `Timeline entry ${index} may not use the reserved category "${entry.category}"`
    );

    // renderTimeline reads tags with ?.forEach, so null and undefined both mean "no tags".
    if (entry.tags != null) {
      assert.ok(Array.isArray(entry.tags), `Timeline entry ${index} tags must be an array when present`);
      // Tags are rendered with textContent.
      entry.tags.forEach((tag, tagIndex) => assertText(tag, `Timeline entry ${index} tag ${tagIndex}`));
    }
  }
});

test('achievements include media, copy, and detail bullet points', () => {
  assertArray(story.achievements, 'Achievements');

  for (const [index, achievement] of story.achievements.entries()) {
    assertMarkupSafeText(achievement?.title, `Achievement ${index} title`);
    assertMarkupSafeText(achievement?.description, `Achievement ${index} description`);
    assertBackgroundImage(achievement?.mediaColor, `Achievement ${index} mediaColor`);
    // setupModal calls achievement.details.map, so a string here throws at click time.
    assertArray(achievement?.details, `Achievement ${index} details`);
    achievement.details.forEach((detail, detailIndex) =>
      assertMarkupSafeText(detail, `Achievement ${index} detail ${detailIndex}`)
    );
  }
});

test('achievement titles stay usable as modal lookup keys', () => {
  // The title is written into data-achievement="..." and is the only key the modal looks
  // up. A quote ends the attribute early. A character reference would be decoded there
  // but not in the raw title, so the lookup would miss or match a different card; the
  // markup check above rules those out, so raw uniqueness here is also decoded uniqueness.
  const titles = story.achievements.map((achievement) => achievement.title);

  assert.equal(new Set(titles).size, titles.length, 'Achievement titles must be unique');
  for (const title of titles) {
    assert.ok(!title.includes('"'), `Achievement title must not contain a double quote: ${title}`);
  }
});

test('skills expose a name, level, and 0-1 progress', () => {
  assertArray(story.skills, 'Skills');

  for (const [index, skill] of story.skills.entries()) {
    assertMarkupSafeText(skill?.name, `Skill ${index} name`);
    assertMarkupSafeText(skill?.level, `Skill ${index} level`);
    // renderSkills writes this straight into transform: scaleX(...).
    assertRatio(skill?.progress, `Skill ${index} progress`);
  }
});

test('toolkit entries include safe destinations', () => {
  assertArray(story.toolkit, 'Toolkit');

  for (const [index, item] of story.toolkit.entries()) {
    assertMarkupSafeText(item?.name, `Toolkit item ${index} name`);
    assertMarkupSafeText(item?.description, `Toolkit item ${index} description`);
    assertLink(item?.link, `Toolkit item ${index} link`);
  }
});
