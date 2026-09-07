# Repository audit

Full audit of every file in this repository (12 files, 1,463 lines). Findings were
produced by four independent reviewers working on separate slices, then put to two
adversarial verifiers whose job was to break them. Only findings that survived
verification appear below; refuted claims are listed at the end so the record is honest.

Ranking is by severity, then by confidence. "Corroborated" means two reviewers who could
not see each other's work found the same defect independently.

---

## Status

Findings 1, 2, 3, and 30 are **fixed**; everything else is still open.

The schema tests now fail on all 14 mutations that the previous suite accepted, including
every one used to demonstrate finding 1. Note what this does and does not cover: the tests
guard the *committed* `data/story.json` against bad edits, but the runtime code is
unchanged — findings 21, 26, and 31 describe `scripts/main.js` still trusting its input,
and they remain open. What finding 3's fix changes is the blast radius: bad input now
costs one section instead of the page.

---

## Blocking

### 1. The test suite passes against a deliberately broken `story.json` — FIXED
`tests/story.test.js`

Nothing in the suite references `story.skills`, though `scripts/main.js:190-201` requires
`skills[].name`, `.level`, and `.progress`. The achievements, signals, and toolkit tests
assert `Array.isArray(...)` and then loop, so an empty array satisfies every assertion
vacuously.

Verified empirically: with `skills` replaced by the string `"this is not even an array"`
and `achievements`, `signals`, and `toolkit` all set to `[]`, the suite still reported
**5/5 passing**.

Combined with finding 3, the consequence is severe: a bad `skills` edit makes
`renderSkills` throw, and the entire page renders as the text
`"skills.forEach is not a function. Please refresh to try again."` — with CI green.

**Fixed.** `tests/story.test.js` was rewritten to assert the contract every renderer in
`scripts/main.js` depends on: non-empty arrays for all six sections, `skills` coverage,
numeric stat values, integer four-digit years, 0–1 ranges for `signal.metric` and
`skill.progress`, `Array.isArray` on `achievement.details`, unique quote-free achievement
titles, and http(s) toolkit links. 9 tests, 15 across the suite, all passing on the real data.

### 2. `engines.node: ">=18"` admits versions where `npm test` cannot run — FIXED
`package.json:11`, `tests/story.test.js:3`

`tests/story.test.js:3` uses the import-attributes syntax
`import story from '../data/story.json' with { type: 'json' }`. That syntax landed in Node
**18.20.0 / 20.10.0 / 21.0.0** (the "Switch from Import Assertions to Import Attributes"
change). Earlier versions cannot parse it.

Verified against real Node binaries:

| Node | Result |
|---|---|
| 18.19.1 | `SyntaxError: Unexpected token 'with'`, exit 1 |
| 20.9.0 | `SyntaxError: Unexpected token 'with'`, exit 1 |
| 18.20.0 | 11/11 pass, exit 0, no flag needed |
| 20.10.0 | 11/11 pass, exit 0 |
| 22.22.2 | 11/11 pass (this is what the repo is developed on, which masks the problem) |

The declared range admits 18.0.0–18.19.x and 20.0.0–20.9.x, all of which hard-fail.

**Fixed.** `engines.node` is now `">=18.20.0 <20.0.0 || >=20.10.0"`. Verified by running the
suite under six real Node builds and checking each against the range with npm's own semver:
the range blocks 18.19.1 and 20.9.0 (both SyntaxError) and admits 18.20.0, 18.20.8, 20.10.0,
and 22.22.2 (15/15 passing) — consistent on all six.

Still open: JSON modules print an `ExperimentalWarning` below Node 18.20.5 / 22.12.0. Move to
`">=22"` to silence it.

---

## High

### 3. One bad field anywhere blanks the entire page — FIXED
`scripts/main.js:284-301` — *corroborated*

`init()` wraps all eleven render and setup calls in a single `try`, and the `catch`
replaces `.hero__content` wholesale via `innerHTML`. Any single failure — a missing
`profile.prompts`, a malformed `skills` array, a failed fetch — destroys the hero, leaves
the other six sections empty, and deletes the theme toggle from the DOM, so nothing on the
page is interactive.

**Fixed.** `setupThemeToggle()` now runs before `loadData()`; the seven sections render
through a `renderSection` helper that catches per section and logs to the console; and the
message goes to a dedicated `.hero__status` live region (`role="alert"`, hidden until
needed) via `textContent` instead of overwriting `.hero__content`.

Verified in headless Chromium against the previous commit, breaking one field
(`skills` set to a string):

| | stats | timeline | achievements | skills | toolkit | toggle | message |
|---|---|---|---|---|---|---|---|
| before | 0 | 5 | 3 | 0 | 0 | destroyed | none |
| after | 4 | 5 | 3 | 0 | 3 | intact | names the failed section |

With `story.json` missing entirely, both versions show the same fetch error, but the theme
toggle now survives instead of being deleted. On good data all sections render and
`.hero__status` stays hidden.

### 4. The deploy manifest omits both modules `main.js` imports
`scripts/deploy.js:25`

The hardcoded `files` array lists only `index.html`, `styles/main.css`, `scripts/main.js`,
and `data/story.json`. It omits `scripts/utils/shuffle.js` and `scripts/utils/stat-format.js`,
which `scripts/main.js:1-2` statically imports. Any host or release step treating
`deploy-manifest.json` as the authoritative upload list ships a `main.js` whose ES imports
404, and the page renders as an empty shell.

**Fix:** generate `files` by walking `distDir` after the copy instead of hardcoding it.

### 5. The build tool is published to the public site
`scripts/deploy.js:36`

The asset list copies all of `scripts/`. Confirmed by a real run: `dist/scripts/deploy.js`
exists in the output, so `/scripts/deploy.js` — including the internal build layout and
deployment instructions — is served to anyone who requests it.

**Fix:** copy `scripts/main.js` and `scripts/utils/` explicitly, or pass a `cp` filter.

### 6. The prompt shuffle is neither a shuffle nor a rotation
`scripts/main.js:229-231`

The handler re-shuffles a fresh copy of `prompts` on every click, then indexes it with an
incrementing counter — so the counter carries no information and each draw is uniform
random. With the 4 prompts in `data/story.json`, every click has a 1-in-4 chance of
redisplaying the prompt already on screen, and `state.currentPromptIndex` no longer
identifies the visible text, so `updatePrompt` and the button disagree about the "current"
prompt. The function also lacks the empty-array guard `updatePrompt` has, so
`(0 + 1) % 0` is `NaN` and an empty `prompts` array renders the literal text `undefined`.

**Fix:** shuffle once into a stored order, re-shuffling only when the index wraps; return
early when the order is empty.

### 7. Unguarded `achievement.details.map` permanently kills the modal
`scripts/main.js:251` — *corroborated*

No existence check, unlike the defensive `item.tags?.forEach` at `scripts/main.js:117`.
The test at `tests/story.test.js:26` uses `assert.ok(achievement.details?.length)`, which
passes for any non-empty **string** — so `details: 'abc'` ships green and then throws
`TypeError` inside the click handler. That handler is outside `init`'s try/catch, so there
is no visible error: the "Explore story" button simply does nothing, forever.

**Fix:** `(achievement.details ?? []).map(...)`, and assert `Array.isArray` in the test.

### 8. Every renderer interpolates story data into `innerHTML` unescaped
`scripts/main.js:31, 69, 109, 173, 193, 214, 248` — *corroborated*

Values reach raw HTML in text, attribute, URL, and CSS positions, including
`data-achievement="${achievement.title}"`, `style="background-image: ${achievement.mediaColor}"`,
and `href="${item.link}"` (a `javascript:` URL sink). A timeline title of
`<img src=x onerror=...>` executes on load.

The data is same-origin and author-controlled today, which caps the immediate risk — but
the README instructs users to customise `story.json`, and the same flaw already causes a
functional bug: an achievement title containing a double quote breaks out of
`data-achievement="..."`, so the lookup at `scripts/main.js:245` misses and the guard at
`:246` silently swallows the click. Duplicate titles open the wrong modal.

**Fix:** build these nodes with `createElement` + `textContent` (as `renderNarrative`
already does for focus items). Key modals on an explicit unique `id`, not the title.

### 9. Primary buttons fail contrast in the dark theme
`styles/main.css:215`

`.button` sets `color: white` over `linear-gradient(135deg, var(--accent), var(--accent-strong))`.
With the dark-default tokens `#38bdf8` / `#0ea5e9` (`styles/main.css:8-9`), the recomputed
WCAG ratios are **2.1:1 and 2.8:1** against a 4.5:1 requirement. This affects every CTA:
"Explore the journey", "Shuffle prompt", "Explore story". The light theme swaps to
`#2563eb`/`#1d4ed8` (5.2:1 / 6.7:1) and passes, so this is dark-theme-only.

**Fix:** use a dark foreground such as `#0f172a` on the accent gradient, or darken the
dark-theme accent tokens to at least `#0369a1`.

### 10. Timeline years are invisible to everyone
`scripts/main.js:108`, `styles/main.css:411-419`

The year is written only to `data-year` and surfaced solely through
`.timeline__item::before { content: attr(data-year) }` at `rgba(148,163,184,0.08)` —
a recomputed **1.05:1**. Generated content is also unreliable for assistive technology.
The result is a chronological timeline that displays no readable dates at all.

**Fix:** render the year as a real element with `textContent` at a legible colour.

### 11. Both content lists expose zero items to assistive technology
`index.html:89`, `index.html:97`

Both containers declare `role="list"`, but the `<article>` children generated at
`scripts/main.js:106` and `:171` carry only a class — there is no `role="listitem"`
anywhere in the file. A screen reader announces "list, 0 items" and list navigation skips
the page's entire main content. The empty-state `<p>` at `:97-99` is a third
non-`listitem` child.

**Fix:** set `role="listitem"` on the generated articles, or drop `role="list"`.

### 12. The achievement dialog has no accessible name
`index.html:126`

`<dialog class="modal" aria-modal="true">` has no `aria-label` or `aria-labelledby`, and
`scripts/main.js:235-262` only writes into `.modal__content` without setting one. On open,
a screen reader announces just "dialog" — the user cannot tell which achievement they
opened. (The `aria-label="Close"` at `index.html:127` names the button, not the dialog.)

**Fix:** give the injected `<h3>` an id and point `aria-labelledby` at it before `showModal()`.

---

## Medium

| # | Location | Defect | Consequence |
|---|---|---|---|
| 13 | `scripts/main.js:281` *(corroborated)* | The `prefers-color-scheme` listener calls `setTheme` unconditionally, discarding a manual toggle; the choice is never persisted | A user who picks dark is silently flipped back to light when their OS auto-switches at sunset |
| 14 | `styles/main.css:387-389` | `.chip--active` is grouped with `.chip:hover` and `.chip:focus-visible` in one rule | While the pointer rests on any chip, the user cannot tell which timeline filter is applied |
| 15 | `styles/main.css:390` | Active-chip white text over the translucent gradient composites to 3.4:1 at the first stop and 4.6:1 at the second | The selected filter's label fails AA across most of its width |
| 16 | `styles/main.css:451` | `.timeline__tag` renders `--accent` at 12.8px on a pale tint — 4.2:1 in the light theme | Tag labels miss AA small-text contrast in light mode (dark theme is 6.6:1 and passes) |
| 17 | `styles/main.css:77` | Hero blobs run `animation: float 16s infinite` and the stylesheet contains no `prefers-reduced-motion` query anywhere (grep-confirmed) | Users with vestibular sensitivity face continuously drifting shapes with no way to stop them |
| 18 | `index.html:86` | `role="toolbar"` with no roving tabindex and no arrow-key handler in `scripts/main.js:129-164` | Keyboard users press the arrow keys the role promises and nothing happens |
| 19 | `index.html:28`, `index.html:78` | `aria-live="polite"` wraps the whole `.hero__stats` and `.signals` containers, which are populated wholesale on first render | Every stat and signal card is read aloud as an unsolicited announcement on page load |
| 20 | `scripts/main.js:198` | Skill meters encode their value only as `transform: scaleX(...)` inside a `role="presentation"` wrapper | Screen reader users hear "Story systems, Lead" and never learn the 92% proficiency |
| 21 | `scripts/main.js:67` | `signal.metric` is unvalidated, and `tests/story.test.js:35` checks only `typeof === 'number'` | A missing metric yields "NaN%"; a percent-style `metric: 78` ships `width: 7800%` and is announced as "7800% confidence" |
| 22 | `scripts/deploy.js:11-39` | `ensureDist()` deletes `dist/` before a non-transactional copy loop | A mid-loop failure leaves a partial `dist/`; observed with `styles/` removed, `dist/` contained only `index.html` |
| 23 | `scripts/deploy.js:27` | Manifest `version` hardcoded to `1.1.0` while `package.json:3` says `1.0.0` | Rollback or incident triage targets a version tag that was never built |
| 24 | `.gitignore` | Ignores only `node_modules/` and `dist/`; `.env`, `*.log`, `.DS_Store` are unignored (confirmed via `git check-ignore`) | A local `.env` holding a hosting token is offered by `git add .` and committed to a public repo |
| 25 | `index.html:20` | The theme toggle ships no `aria-pressed`; it is first set at `scripts/main.js:271`, after `loadData()` resolves | Before JS runs — and permanently on the error path — the control is announced as a plain button with no state |
| 26 | `scripts/main.js:178` | Modals are keyed on `achievement.title`, with no uniqueness or quote constraint | Duplicate titles open the wrong modal; a quote in a title breaks the lookup silently |

---

## Low

| # | Location | Defect |
|---|---|---|
| 27 | `scripts/main.js:103-104` *(corroborated)* | When `filter === 'all'`, `filtered` is the same reference as `state.data.timeline`, so `.sort()` mutates the loaded data in place — the authored order is unrecoverable. Sort a copy |
| 28 | `scripts/utils/stat-format.js:6` *(corroborated)* | The suffix table stops at `b`, so `1e12` renders as `"1000b"` and `1e15` as `"1000000b"`. Add a `t` suffix or fall back to `Intl.NumberFormat` compact notation |
| 29 | `scripts/utils/stat-format.js:26-28, 31` | Dead code: the second loop only runs when `\|rounded\| >= 1000`, so `scaled` always has `\|scaled\| >= 1` and can never round to `-0`; likewise `.replace(/\.0$/, '')` can never fire because a non-integer `rounded` always has a nonzero tenths digit. Both advertise guarded paths that no input reaches |
| 30 | `scripts/main.js:300` | **FIXED** as part of finding 3 — the failure path interpolated `error.message` into `innerHTML`; `showStatus` now uses `textContent` |
| 31 | `scripts/main.js:139-146` | A timeline entry with `category: "all"` adds a second `[data-filter="all"]` chip, so both mark active and that category can never be selected alone |
| 32 | `package.json` | No `"private": true` on a package with no `main` and no `files`, so an accidental `npm publish` pushes personal content to the public registry |
| 33 | `README.md:21, 33` | Claims `npm test` "validates the story data structure" (it never touches `profile.stats`, `summary`, `tagline`, `skills`, or `mediaColor`), and advertises toolkit entries as downloadable resources while all three `link` values in `data/story.json` are `https://example.com/...` placeholders rendered as live anchors |
| 34 | `scripts/deploy.js:15-19` | `copyAsset()` has no `path.relative` containment assertion. Not exploitable today — the asset list is a hardcoded literal — but a `../` entry would write outside the repo the moment that list is sourced from config |
| 35 | `scripts/main.js:162` | Re-rendering `.timeline` on filter change moves no focus and triggers no live region, so the "No entries for this chapter yet" empty state is announced to no one |

---

## Refuted, and corrections to the record

These were proposed during the audit and did **not** survive verification. They are listed
so nobody re-reports them.

- **`shuffle.js` is biased.** Refuted. It is a correct, unbiased, non-mutating Fisher-Yates:
  descending index, `j` drawn from `[0, index]` inclusive.
- **The "All" chip lacks `chip--active` on load.** Refuted. `index.html:86` ships
  `class="chip chip--active"` in the markup.
- **`with { type: 'json' }` is flag-gated behind `--experimental-import-attributes` on
  Node 18.20+.** Refuted. That flag does not exist — 18.20.0, 20.9.0, 20.10.0, and 22.22.2
  all reject it with `bad option`. The syntax simply works unflagged from 18.20.0 / 20.10.0.
  Finding 2 stands on the version boundary alone.
- **`fs.cp` instability justifies requiring Node >= 22.** Refuted. `fs.cp` was added in
  16.7.0 and stabilised in 22.3.0, but experimental never meant unavailable —
  `node scripts/deploy.js` ran successfully on 18.19.1.
- **JS/markup selector mismatches.** None found. Every class and dataset key `main.js`
  reads exists in the markup or in markup it generates.
- **Horizontal overflow at 320px.** None found. The widest minimum grid track is 260px
  inside 280px of content box; the modal is `min(560px, 90vw)` = 288px; `.hero__stats`
  wraps rather than overflowing.
- **Production 404s from files the deploy script fails to copy.** None. A real
  `npm run deploy` produced all assets `index.html` references. The manifest is wrong
  (finding 4), but the copy itself is complete.
- **Active-chip contrast is uniformly 3.4:1.** Corrected: it is 3.4:1 at the first gradient
  stop and 4.6:1 at the second.
- **`node --test` with no path argument might miss a test file.** Refuted for this repo.
  The default discovery patterns pick up both files; the observed run is 11/11.

---

## Coverage

All 12 files were reviewed; no file was skipped and no reviewer failed to report.

`index.html` · `styles/main.css` · `scripts/main.js` · `scripts/deploy.js` ·
`scripts/utils/shuffle.js` · `scripts/utils/stat-format.js` · `tests/story.test.js` ·
`tests/stat-format.test.js` · `data/story.json` · `package.json` · `.gitignore` · `README.md`

**Not covered**, and worth a follow-up: the contrast, ARIA, and layout findings are derived
from source rather than from a browser or a screen reader, and no cross-browser or
real-device testing was done. Headless Chromium was used only to verify finding 3's fix.
There is no CI workflow in the repository (`.github/` is absent), so none of the above is
enforced on push.

**Baseline:** `npm test` on Node 22.22.2 → 11 tests, 11 pass, 0 fail, ~160ms.
`npm run deploy` → exit 0, 8 files in `dist/`.
