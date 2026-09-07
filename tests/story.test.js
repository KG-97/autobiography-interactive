import test from 'node:test';
import assert from 'node:assert/strict';
import story from '../data/story.json' with { type: 'json' };

// These tests describe the contract scripts/main.js relies on. Every field asserted
// here is read by a renderer, so a failure means the page would break or render
// placeholder text rather than that the data is merely untidy.

function assertText(value, label) {
  assert.equal(typeof value, 'string', `${label} must be a string`);
  assert.ok(value.trim(), `${label} must not be empty`);
}

function assertFilledArray(value, label, minimum = 1) {
  assert.ok(Array.isArray(value), `${label} must be an array`);
  assert.ok(value.length >= minimum, `${label} must include at least ${minimum} entr${minimum === 1 ? 'y' : 'ies'}`);
}

function assertRatio(value, label) {
  assert.equal(typeof value, 'number', `${label} must be a number`);
  assert.ok(Number.isFinite(value), `${label} must be finite`);
  assert.ok(value >= 0 && value <= 1, `${label} must fall between 0 and 1, received ${value}`);
}

test('profile provides the headline copy', () => {
  assertText(story.profile?.name, 'Profile name');
  assertText(story.profile?.tagline, 'Profile tagline');
  assertText(story.profile?.summary, 'Profile summary');
});

test('profile stats carry a label and a numeric value', () => {
  assertFilledArray(story.profile?.stats, 'Profile stats');

  for (const [index, stat] of story.profile.stats.entries()) {
    assertText(stat?.label, `Stat ${index} label`);
    assert.equal(typeof stat?.value, 'number', `Stat ${index} value must be a number`);
    assert.ok(Number.isFinite(stat.value), `Stat ${index} value must be finite`);
  }
});

test('profile includes prompts and focus areas', () => {
  assertFilledArray(story.profile?.prompts, 'Prompts', 3);
  assertFilledArray(story.profile?.focus, 'Focus');

  story.profile.prompts.forEach((prompt, index) => assertText(prompt, `Prompt ${index}`));
  story.profile.focus.forEach((item, index) => assertText(item, `Focus area ${index}`));
});

test('signals track cadence and a 0-1 metric', () => {
  assertFilledArray(story.signals, 'Signals');

  for (const [index, signal] of story.signals.entries()) {
    assertText(signal?.title, `Signal ${index} title`);
    assertText(signal?.cadence, `Signal ${index} cadence`);
    assertText(signal?.description, `Signal ${index} description`);
    assertRatio(signal?.metric, `Signal ${index} metric`);
  }
});

test('timeline entries include a sortable year and essential fields', () => {
  assertFilledArray(story.timeline, 'Timeline', 3);

  for (const [index, entry] of story.timeline.entries()) {
    // renderTimeline sorts with (a, b) => a.year - b.year, so a non-numeric year
    // silently produces a NaN comparator and an unordered timeline.
    assert.ok(Number.isInteger(entry?.year), `Timeline entry ${index} year must be an integer`);
    assert.ok(entry.year >= 1000 && entry.year <= 9999, `Timeline entry ${index} year must be a four-digit year`);
    assertText(entry?.title, `Timeline entry ${index} title`);
    assertText(entry?.description, `Timeline entry ${index} description`);
    assertText(entry?.category, `Timeline entry ${index} category`);
    // "all" is reserved for the default filter chip in index.html.
    assert.notEqual(entry.category, 'all', `Timeline entry ${index} may not use the reserved category "all"`);

    if (entry.tags !== undefined) {
      assert.ok(Array.isArray(entry.tags), `Timeline entry ${index} tags must be an array when present`);
      entry.tags.forEach((tag, tagIndex) => assertText(tag, `Timeline entry ${index} tag ${tagIndex}`));
    }
  }
});

test('achievements include media, copy, and detail bullet points', () => {
  assertFilledArray(story.achievements, 'Achievements');

  for (const [index, achievement] of story.achievements.entries()) {
    assertText(achievement?.title, `Achievement ${index} title`);
    assertText(achievement?.description, `Achievement ${index} description`);
    assertText(achievement?.mediaColor, `Achievement ${index} mediaColor`);
    // setupModal calls achievement.details.map, so a string here throws at click time.
    assertFilledArray(achievement?.details, `Achievement ${index} details`);
    achievement.details.forEach((detail, detailIndex) =>
      assertText(detail, `Achievement ${index} detail ${detailIndex}`)
    );
  }
});

test('achievement titles stay usable as modal lookup keys', () => {
  // The title is interpolated into data-achievement="..." and is the sole key the
  // modal looks up, so duplicates open the wrong entry and quotes break the attribute.
  const titles = story.achievements.map((achievement) => achievement.title);

  assert.equal(new Set(titles).size, titles.length, 'Achievement titles must be unique');
  for (const title of titles) {
    assert.ok(!title.includes('"'), `Achievement title must not contain a double quote: ${title}`);
  }
});

test('skills expose a name, level, and 0-1 progress', () => {
  assertFilledArray(story.skills, 'Skills');

  for (const [index, skill] of story.skills.entries()) {
    assertText(skill?.name, `Skill ${index} name`);
    assertText(skill?.level, `Skill ${index} level`);
    // renderSkills writes this straight into transform: scaleX(...).
    assertRatio(skill?.progress, `Skill ${index} progress`);
  }
});

test('toolkit entries include destinations', () => {
  assertFilledArray(story.toolkit, 'Toolkit');

  for (const [index, item] of story.toolkit.entries()) {
    assertText(item?.name, `Toolkit item ${index} name`);
    assertText(item?.description, `Toolkit item ${index} description`);
    assert.ok(
      /^https?:\/\/\S+$/.test(item?.link ?? ''),
      `Toolkit item ${index} must link to an http(s) URL`
    );
  }
});
