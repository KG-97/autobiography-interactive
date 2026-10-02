import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import story from '../data/story.json' with { type: 'json' };
import { formatStatValue } from '../scripts/utils/stat-format.js';

// Renders index.html with scripts/main.js against story data in jsdom and checks what a
// visitor would actually get. The data tests check values; these check the page.

const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const mainUrl = new URL('../scripts/main.js', import.meta.url).href;
let renderCount = 0;

async function settle() {
  // init() only awaits the fetch stub's promises, so one macrotask flushes it fully.
  await new Promise((resolve) => setTimeout(resolve, 0));
}

async function renderPage(storyData, { fetchStatus = 200, matchMedia = true } = {}) {
  const dom = new JSDOM(indexHtml, { url: 'http://localhost/' });
  const { window } = dom;
  // jsdom fires its own DOMContentLoaded asynchronously; let it pass before main.js
  // listens, so init() runs exactly once, from the event dispatched below.
  if (window.document.readyState !== 'complete') {
    await new Promise((resolve) => window.addEventListener('load', resolve, { once: true }));
  }

  // jsdom implements neither <dialog> modality, matchMedia, nor fetch. These stand-ins do
  // the minimum main.js relies on.
  window.HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  window.HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
  window.matchMedia = matchMedia ? () => ({ matches: false, addEventListener() {} }) : undefined;

  globalThis.window = window;
  globalThis.document = window.document;
  globalThis.HTMLButtonElement = window.HTMLButtonElement;
  globalThis.fetch = async () => ({
    ok: fetchStatus === 200,
    status: fetchStatus,
    json: async () => structuredClone(storyData)
  });

  // A fresh module instance per render, so main.js's module state starts clean.
  await import(`${mainUrl}?render=${++renderCount}`);
  window.dispatchEvent(new window.Event('DOMContentLoaded'));
  await settle();
  return window.document;
}

const texts = (doc, selector) => [...doc.querySelectorAll(selector)].map((node) => node.textContent);

// jsdom applies no layout, so visibility here means "not inside a [hidden] element".
// Chromium was used separately to confirm the stylesheet really hides [hidden] elements.
const visible = (element) => Boolean(element) && !element.closest('[hidden]');

// Clicks every control a visitor can see and fails on any that does nothing.
function assertNoDeadControls(doc, data) {
  const modal = doc.querySelector('.modal');
  for (const button of doc.querySelectorAll('.achievement__cta')) {
    if (!visible(button)) continue;
    button.click();
    assert.ok(modal.hasAttribute('open'), `"Explore story" for "${button.dataset.achievement}" opens the modal`);
    doc.querySelector('.modal__close').click();
  }

  const controls = doc.querySelector('.timeline__controls');
  if (visible(controls)) {
    for (const chip of controls.querySelectorAll('.chip')) {
      chip.click();
      assert.equal(chip.getAttribute('aria-pressed'), 'true', `the "${chip.dataset.filter}" filter responds`);
    }
  }

  const shuffle = doc.querySelector('.narrative__shuffle');
  if (visible(shuffle)) {
    shuffle.click();
    const prompt = doc.querySelector('.narrative__prompt').textContent;
    assert.ok((data?.profile?.prompts ?? []).includes(prompt), `"Shuffle prompt" shows a prompt, got "${prompt}"`);
  }

  const toggle = doc.querySelector('.theme-toggle');
  if (visible(toggle)) {
    const wasLight = doc.documentElement.classList.contains('light');
    toggle.click();
    assert.notEqual(doc.documentElement.classList.contains('light'), wasLight, 'the theme toggle switches theme');
  }
}

// A section shows either everything or nothing, never a fragment of its list.
function assertWholeOrEmpty(doc, data) {
  for (const [selector, list] of [
    ['.stat', data.profile?.stats],
    ['.signal', data.signals],
    ['.timeline__item', data.timeline],
    ['.achievement', data.achievements],
    ['.skill', data.skills],
    ['.tool', data.toolkit]
  ]) {
    const count = doc.querySelectorAll(selector).length;
    assert.ok(count === 0 || count === list?.length, `${selector}: ${count} of ${list?.length} rendered`);
  }
}

test('renders every section of story.json', async () => {
  const doc = await renderPage(story);

  assert.equal(doc.querySelector('.hero__title').textContent, story.profile.name);
  assert.equal(doc.querySelectorAll('.stat').length, story.profile.stats.length);
  assert.equal(doc.querySelectorAll('.signal').length, story.signals.length);
  assert.equal(doc.querySelectorAll('.timeline__item').length, story.timeline.length);
  assert.equal(doc.querySelectorAll('.achievement').length, story.achievements.length);
  assert.equal(doc.querySelectorAll('.skill').length, story.skills.length);
  assert.equal(doc.querySelectorAll('.tool').length, story.toolkit.length);

  const categories = new Set(story.timeline.map((entry) => entry.category));
  assert.equal(doc.querySelectorAll('.timeline__controls .chip').length, categories.size + 1, 'one chip per category plus "All"');
  assert.ok(doc.querySelector('.narrative__prompt').textContent.trim(), 'a prompt is shown');
  assert.equal(doc.querySelector('.hero__status').hidden, true, 'no error status on good data');
});

test('renders story text as text, not as markup', async () => {
  // Most renderers use innerHTML. If any string were parsed as markup or had a character
  // reference decoded, the text a visitor sees would differ from the data.
  const doc = await renderPage(story);
  const byYear = [...story.timeline].sort((a, b) => a.year - b.year);

  assert.deepEqual(texts(doc, '.stat__label'), story.profile.stats.map((stat) => stat.label));
  assert.deepEqual(texts(doc, '.stat__value'), story.profile.stats.map((stat) => formatStatValue(stat.value)));
  assert.deepEqual(texts(doc, '.signal__title'), story.signals.map((signal) => signal.title));
  assert.deepEqual(texts(doc, '.signal__description'), story.signals.map((signal) => signal.description));
  assert.deepEqual(texts(doc, '.timeline__title'), byYear.map((entry) => entry.title));
  assert.deepEqual(texts(doc, '.timeline__description'), byYear.map((entry) => entry.description));
  assert.deepEqual(texts(doc, '.achievement__title'), story.achievements.map((achievement) => achievement.title));
  assert.deepEqual(texts(doc, '.skill__name'), story.skills.map((skill) => skill.name));
  assert.deepEqual(texts(doc, '.tool__name'), story.toolkit.map((item) => item.name));
  assert.deepEqual(
    [...doc.querySelectorAll('.tool__link')].map((link) => link.getAttribute('href')),
    story.toolkit.map((item) => item.link)
  );
});

test('each "Explore story" button opens its own achievement', async () => {
  const doc = await renderPage(story);
  const modal = doc.querySelector('.modal');
  const buttons = doc.querySelectorAll('.achievement__cta');
  assert.equal(buttons.length, story.achievements.length);

  for (const [index, button] of [...buttons].entries()) {
    const achievement = story.achievements[index];
    button.click();
    assert.ok(modal.hasAttribute('open'), `button ${index} opens the modal`);
    assert.equal(modal.querySelector('.modal__content h3').textContent, achievement.title, `button ${index} shows its own title`);
    assert.deepEqual(texts(modal, '.modal__content li'), achievement.details, `button ${index} shows its own details`);
    modal.querySelector('.modal__close').click();
    assert.ok(!modal.hasAttribute('open'), 'the close button closes the modal');
  }
});

test('timeline filters show only the chosen category', async () => {
  const doc = await renderPage(story);
  const chips = [...doc.querySelectorAll('.timeline__controls .chip')];

  for (const chip of chips) {
    chip.click();
    const filter = chip.dataset.filter;
    const expected = filter === 'all' ? story.timeline : story.timeline.filter((entry) => entry.category === filter);
    const shown = texts(doc, '.timeline__item .timeline__category');

    assert.equal(shown.length, expected.length, `"${filter}" shows ${expected.length} entries`);
    if (filter !== 'all') {
      assert.ok(shown.every((category) => category === filter), `"${filter}" shows only its own entries`);
    }
    for (const other of chips) {
      assert.equal(other.getAttribute('aria-pressed'), String(other === chip), `only "${filter}" is marked pressed`);
    }
  }
});

test('a malformed section fails alone and is reported', async (t) => {
  t.mock.method(console, 'error', () => {});
  const doc = await renderPage({ ...structuredClone(story), skills: 'not a list' });

  assert.equal(doc.querySelectorAll('.skill').length, 0);
  assert.equal(doc.querySelectorAll('.stat').length, story.profile.stats.length, 'the hero still renders');
  assert.equal(doc.querySelectorAll('.timeline__item').length, story.timeline.length, 'the timeline still renders');
  assert.equal(doc.querySelectorAll('.tool').length, story.toolkit.length, 'the toolkit still renders');
  assert.ok(doc.querySelector('.theme-toggle'), 'the theme toggle survives');

  const status = doc.querySelector('.hero__status');
  assert.equal(status.hidden, false);
  assert.match(status.textContent, /could not be fully displayed: skills\./);
});

test('a failed fetch is reported and keeps the theme toggle', async () => {
  const doc = await renderPage(story, { fetchStatus: 404 });

  assert.ok(doc.querySelector('.theme-toggle'), 'the theme toggle survives');
  assert.match(doc.querySelector('.hero__status').textContent, /Failed to load story data: 404/);
});

test('data that is not an object is reported as malformed', async () => {
  const doc = await renderPage(null);

  assert.match(doc.querySelector('.hero__status').textContent, /empty or malformed/);
});

test('every control works on the real data', async () => {
  const doc = await renderPage(story);
  assertNoDeadControls(doc, story);
});

// Each case breaks data part-way through a section, past the point where the old
// renderers had already put content or controls on the page (audit findings R1 and R3).
const partialFailures = [
  ['an achievement that is null', 'achievements', (data) => { data.achievements[1] = null; }],
  ['a timeline entry that is null', 'timeline', (data) => { data.timeline[2] = null; }],
  ['timeline tags that are not a list', 'timeline', (data) => { data.timeline[4].tags = 'immersive'; }],
  ['a stat that is null', 'hero', (data) => { data.profile.stats[2] = null; }],
  ['a focus list that is not a list', 'narrative', (data) => { data.profile.focus = 'not a list'; }],
  ['missing prompts', 'prompts', (data) => { delete data.profile.prompts; }]
];

for (const [name, section, breakData] of partialFailures) {
  test(`${name}: the section fails whole and leaves no dead controls`, async (t) => {
    t.mock.method(console, 'error', () => {});
    const data = structuredClone(story);
    breakData(data);
    const doc = await renderPage(data);

    assert.match(doc.querySelector('.hero__status').textContent, new RegExp(`: (.*, )?${section}(,|\\.)`));
    assertWholeOrEmpty(doc, data);
    assertNoDeadControls(doc, data);
  });
}

test('a broken focus list does not take the prompt down with it', async (t) => {
  t.mock.method(console, 'error', () => {});
  const data = structuredClone(story);
  data.profile.focus = 'not a list';
  const doc = await renderPage(data);

  assert.ok(story.profile.prompts.includes(doc.querySelector('.narrative__prompt').textContent), 'a prompt is shown');
  assert.ok(visible(doc.querySelector('.narrative__shuffle')), 'the shuffle button is still offered');
});

test('a theme toggle that cannot be set up is hidden rather than left inert', async (t) => {
  t.mock.method(console, 'error', () => {});
  const doc = await renderPage(story, { matchMedia: false });

  assert.ok(!visible(doc.querySelector('.theme-toggle')));
  assert.equal(doc.querySelectorAll('.achievement').length, story.achievements.length, 'the rest of the page renders');
  assertNoDeadControls(doc, story);
});

test('an error when opening a story is reported, not silent', async (t) => {
  // Bypasses the data tests on purpose: the page must still not fail silently (audit finding R2).
  t.mock.method(console, 'error', () => {});
  const data = structuredClone(story);
  data.achievements[0].details = 'not a list';
  const doc = await renderPage(data);

  doc.querySelector('.achievement__cta').click();
  const status = doc.querySelector('.hero__status');
  assert.equal(status.hidden, false);
  assert.match(status.textContent, /Could not open that story/);
});
