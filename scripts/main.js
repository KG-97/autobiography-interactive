import { shuffle } from './utils/shuffle.js';
import { formatStatValue } from './utils/stat-format.js';

const state = {
  data: null,
  currentPromptIndex: 0,
  activeFilter: 'all'
};

async function loadData() {
  const response = await fetch('data/story.json');
  if (!response.ok) {
    throw new Error(`Failed to load story data: ${response.status}`);
  }

  const data = await response.json();
  state.data = data;
  return data;
}

function renderHero(profile) {
  const stats = document.createDocumentFragment();

  profile.stats.forEach((stat) => {
    const statElement = document.createElement('div');
    statElement.className = 'stat';
    statElement.innerHTML = `
      <span class="stat__label">${stat.label}</span>
      <span class="stat__value">${formatStatValue(stat.value)}</span>
    `;
    stats.appendChild(statElement);
  });

  document.querySelector('.hero__title').textContent = profile.name;
  document.querySelector('.hero__subtitle').textContent = profile.tagline;
  document.querySelector('.hero__stats').replaceChildren(stats);
}

function renderNarrative(profile) {
  const focus = document.createDocumentFragment();
  profile.focus.forEach((item) => {
    const li = document.createElement('li');
    li.textContent = item;
    focus.appendChild(li);
  });

  document.querySelector('.narrative__summary').textContent = profile.summary;
  document.querySelector('.narrative__focus').replaceChildren(focus);
}

// Kept apart from the summary and focus list, so a problem in either of those cannot
// leave the prompt empty and the shuffle button doing nothing.
function renderPrompts(prompts) {
  state.currentPromptIndex = 0;
  updatePrompt(prompts);
  setupPromptShuffle(prompts);
}

function updatePrompt(prompts) {
  if (!prompts.length) return;
  const prompt = prompts[state.currentPromptIndex % prompts.length];
  document.querySelector('.narrative__prompt').textContent = prompt;
}

function renderSignals(signals) {
  const fragment = document.createDocumentFragment();

  signals.forEach((signal) => {
    const article = document.createElement('article');
    article.className = 'signal';
    const percentage = Math.round(signal.metric * 100);

    article.innerHTML = `
      <div class="signal__header">
        <div>
          <p class="signal__cadence">${signal.cadence}</p>
          <h3 class="signal__title">${signal.title}</h3>
        </div>
        <span class="signal__metric" aria-label="${percentage}% confidence">${percentage}%</span>
      </div>
      <p class="signal__description">${signal.description}</p>
      <div class="signal__progress" role="presentation">
        <div class="signal__progress-bar" style="width: ${percentage}%"></div>
      </div>
    `;

    fragment.appendChild(article);
  });

  document.querySelector('.signals').replaceChildren(fragment);
}

function renderTimeline(timeline, filter = 'all') {
  const container = document.querySelector('.timeline');
  const fragment = document.createDocumentFragment();

  const filtered =
    filter === 'all'
      ? timeline
      : timeline.filter((item) => item.category === filter);

  if (!filtered.length) {
    const empty = document.createElement('p');
    empty.textContent = 'No entries for this chapter yet. Check back soon!';
    container.replaceChildren(empty);
    return;
  }

  filtered
    .sort((a, b) => a.year - b.year)
    .forEach((item) => {
      const article = document.createElement('article');
      article.className = 'timeline__item';
      article.innerHTML = `
        <span class="timeline__category">${item.category}</span>
        <h3 class="timeline__title">${item.title}</h3>
        <p class="timeline__description">${item.description}</p>
      `;

      // Set with textContent rather than interpolated into the markup above, so the year
      // adds no new innerHTML input (audit finding 8).
      const year = document.createElement('time');
      year.className = 'timeline__year';
      year.textContent = item.year;
      article.prepend(year);

      const tags = document.createElement('ul');
      tags.className = 'timeline__tags';
      item.tags?.forEach((tag) => {
        const li = document.createElement('li');
        li.className = 'timeline__tag';
        li.textContent = tag;
        tags.appendChild(li);
      });

      article.appendChild(tags);
      fragment.appendChild(article);
    });

  container.replaceChildren(fragment);
}

function renderFilters(timeline) {
  const controls = document.querySelector('.timeline__controls');
  controls.querySelectorAll('.chip').forEach((chip) => chip.setAttribute('aria-pressed', 'false'));
  const defaultChip = controls.querySelector('[data-filter="all"]');
  if (defaultChip) {
    defaultChip.setAttribute('aria-pressed', 'true');
  }

  const categories = Array.from(new Set(timeline.map((item) => item.category)));
  const chips = document.createDocumentFragment();

  categories.forEach((category) => {
    const button = document.createElement('button');
    button.className = 'chip';
    button.dataset.filter = category;
    button.textContent = category;
    button.setAttribute('aria-pressed', 'false');
    chips.appendChild(button);
  });

  controls.addEventListener('click', guarded('filter the timeline', (event) => {
    if (!(event.target instanceof HTMLButtonElement)) return;

    const { filter } = event.target.dataset;
    state.activeFilter = filter;

    controls
      .querySelectorAll('.chip')
      .forEach((chip) => {
        const isActive = chip.dataset.filter === filter;
        chip.classList.toggle('chip--active', isActive);
        chip.setAttribute('aria-pressed', String(isActive));
      });

    renderTimeline(state.data.timeline, filter);
  }));
  controls.appendChild(chips);
}

function renderAchievements(achievements) {
  const fragment = document.createDocumentFragment();

  achievements.forEach((achievement) => {
    const card = document.createElement('article');
    card.className = 'achievement';
    card.innerHTML = `
      <div class="achievement__media" style="background-image: ${achievement.mediaColor}"></div>
      <div class="achievement__body">
        <h3 class="achievement__title">${achievement.title}</h3>
        <p>${achievement.description}</p>
        <button class="button achievement__cta" data-achievement="${achievement.title}">Explore story</button>
      </div>
    `;

    fragment.appendChild(card);
  });

  document.querySelector('.achievements').replaceChildren(fragment);
}

function renderSkills(skills) {
  const fragment = document.createDocumentFragment();

  skills.forEach((skill) => {
    const skillElement = document.createElement('article');
    skillElement.className = 'skill';
    skillElement.innerHTML = `
      <div class="skill__header">
        <span class="skill__name">${skill.name}</span>
        <span class="skill__level">${skill.level}</span>
      </div>
      <div class="skill__progress" role="presentation">
        <div class="skill__progress-bar" style="transform: scaleX(${skill.progress})"></div>
      </div>
    `;

    fragment.appendChild(skillElement);
  });

  document.querySelector('.skills').replaceChildren(fragment);
}

function renderToolkit(toolkit) {
  const fragment = document.createDocumentFragment();

  toolkit.forEach((item) => {
    const card = document.createElement('article');
    card.className = 'tool';
    card.innerHTML = `
      <div>
        <h3 class="tool__name">${item.name}</h3>
        <p class="tool__description">${item.description}</p>
      </div>
      <a class="tool__link" href="${item.link}" target="_blank" rel="noreferrer">Open</a>
    `;

    fragment.appendChild(card);
  });

  document.querySelector('.toolkit').replaceChildren(fragment);
}

function setupPromptShuffle(prompts) {
  const button = document.querySelector('.narrative__shuffle');
  button.addEventListener('click', guarded('shuffle the prompt', () => {
    const order = shuffle([...prompts]);
    state.currentPromptIndex = (state.currentPromptIndex + 1) % order.length;
    document.querySelector('.narrative__prompt').textContent = order[state.currentPromptIndex];
  }));
}

function setupModal(achievements) {
  const modal = document.querySelector('.modal');
  const closeButton = modal.querySelector('.modal__close');
  const content = modal.querySelector('.modal__content');

  document.body.addEventListener('click', guarded('open that story', (event) => {
    const target = event.target;
    if (!(target instanceof HTMLButtonElement)) return;

    if (target.classList.contains('achievement__cta')) {
      const achievement = achievements.find((item) => item.title === target.dataset.achievement);
      if (!achievement) return;

      content.innerHTML = `
        <h3>${achievement.title}</h3>
        <p>${achievement.description}</p>
        <ul>${achievement.details.map((detail) => `<li>${detail}</li>`).join('')}</ul>
      `;
      modal.showModal();
    }
  }));

  closeButton.addEventListener('click', () => modal.close());
  modal.addEventListener('cancel', (event) => {
    event.preventDefault();
    modal.close();
  });
}

function setupThemeToggle() {
  const toggle = document.querySelector('.theme-toggle');
  const root = document.documentElement;
  const prefersLight = window.matchMedia('(prefers-color-scheme: light)');

  function setTheme(lightMode) {
    root.classList.toggle('light', lightMode);
    toggle.setAttribute('aria-pressed', String(lightMode));
  }

  setTheme(prefersLight.matches);

  toggle.addEventListener('click', guarded('switch the theme', () => {
    const isLight = root.classList.toggle('light');
    toggle.setAttribute('aria-pressed', String(isLight));
  }));

  prefersLight.addEventListener('change', (event) => setTheme(event.matches));
}

function showStatus(message) {
  const status = document.querySelector('.hero__status');
  if (!status) return;

  // textContent, not innerHTML: error messages can carry markup from a failed response body.
  status.textContent = message;
  status.hidden = false;
}

function hide(selector) {
  const element = document.querySelector(selector);
  if (element) element.hidden = true;
}

// Event handlers run after init() has finished, outside renderSection, so a failure in
// one would otherwise be silent and leave its control looking broken. Report it instead.
function guarded(action, handler) {
  return (event) => {
    try {
      handler(event);
    } catch (error) {
      console.error(`Failed to ${action}`, error);
      showStatus(`Could not ${action}. Please refresh to try again.`);
    }
  };
}

// Each section renders independently so that one malformed field degrades that
// section alone instead of taking the whole page down with it.
function renderSection(label, render) {
  try {
    render();
    return true;
  } catch (error) {
    console.error(`Failed to render the ${label} section`, error);
    return false;
  }
}

async function init() {
  // Bound before the data load so the page stays usable even if the fetch fails. If it
  // cannot be set up, hide it rather than leave a button that does nothing.
  if (!renderSection('theme toggle', setupThemeToggle)) {
    hide('.theme-toggle');
  }

  let data;
  try {
    data = await loadData();
  } catch (error) {
    showStatus(`${error.message}. Please refresh to try again.`);
    return;
  }

  if (!data || typeof data !== 'object') {
    showStatus('Story data is empty or malformed. Please refresh to try again.');
    return;
  }

  // Each renderer builds its content off-page and swaps it in only once complete, so a
  // failed section shows nothing rather than half its content. Controls that are part of
  // the markup itself would survive a failure with nothing behind them, so the third
  // entry names the ones to hide when that happens.
  const sections = [
    ['hero', () => renderHero(data.profile)],
    ['narrative', () => renderNarrative(data.profile)],
    ['prompts', () => renderPrompts(data.profile.prompts), '.narrative__card--prompt'],
    ['signals', () => renderSignals(data.signals)],
    [
      'timeline',
      () => {
        renderTimeline(data.timeline, state.activeFilter);
        renderFilters(data.timeline);
      },
      '.timeline__controls'
    ],
    [
      'achievements',
      () => {
        // Bound first: if the cards then fail, none are shown, so no button is left inert.
        setupModal(data.achievements);
        renderAchievements(data.achievements);
      }
    ],
    ['skills', () => renderSkills(data.skills)],
    ['toolkit', () => renderToolkit(data.toolkit)]
  ];

  const failed = [];
  for (const [label, render, controls] of sections) {
    if (!renderSection(label, render)) {
      failed.push(label);
      if (controls) hide(controls);
    }
  }

  if (failed.length === sections.length) {
    showStatus('None of the story sections could be displayed. Please refresh to try again.');
  } else if (failed.length) {
    // "Fully": a section can fail part-way and leave some of its content on the page.
    showStatus(`Some sections could not be fully displayed: ${failed.join(', ')}.`);
  }
}

window.addEventListener('DOMContentLoaded', init);
