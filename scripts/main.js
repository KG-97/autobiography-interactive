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
  document.querySelector('.hero__title').textContent = profile.name;
  document.querySelector('.hero__subtitle').textContent = profile.tagline;

  const stats = document.querySelector('.hero__stats');
  stats.innerHTML = '';

  profile.stats.forEach((stat) => {
    const statElement = document.createElement('div');
    statElement.className = 'stat';
    statElement.innerHTML = `
      <span class="stat__label">${stat.label}</span>
      <span class="stat__value">${formatStatValue(stat.value)}</span>
    `;
    stats.appendChild(statElement);
  });
}

function renderNarrative(profile) {
  document.querySelector('.narrative__summary').textContent = profile.summary;

  const focusList = document.querySelector('.narrative__focus');
  focusList.innerHTML = '';
  profile.focus.forEach((item) => {
    const li = document.createElement('li');
    li.textContent = item;
    focusList.appendChild(li);
  });

  state.currentPromptIndex = 0;
  updatePrompt(profile.prompts);
}

function updatePrompt(prompts) {
  if (!prompts.length) return;
  const prompt = prompts[state.currentPromptIndex % prompts.length];
  document.querySelector('.narrative__prompt').textContent = prompt;
}

function renderSignals(signals) {
  const container = document.querySelector('.signals');
  container.innerHTML = '';

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

    container.appendChild(article);
  });
}

function renderTimeline(timeline, filter = 'all') {
  const container = document.querySelector('.timeline');
  container.innerHTML = '';

  const filtered =
    filter === 'all'
      ? timeline
      : timeline.filter((item) => item.category === filter);

  if (!filtered.length) {
    const empty = document.createElement('p');
    empty.textContent = 'No entries for this chapter yet. Check back soon!';
    container.appendChild(empty);
    return;
  }

  filtered
    .sort((a, b) => a.year - b.year)
    .forEach((item) => {
      const article = document.createElement('article');
      article.className = 'timeline__item';
      article.dataset.year = item.year;
      article.innerHTML = `
        <span class="timeline__category">${item.category}</span>
        <h3 class="timeline__title">${item.title}</h3>
        <p class="timeline__description">${item.description}</p>
      `;

      const tags = document.createElement('ul');
      tags.className = 'timeline__tags';
      item.tags?.forEach((tag) => {
        const li = document.createElement('li');
        li.className = 'timeline__tag';
        li.textContent = tag;
        tags.appendChild(li);
      });

      article.appendChild(tags);
      container.appendChild(article);
    });
}

function renderFilters(timeline) {
  const controls = document.querySelector('.timeline__controls');
  controls.querySelectorAll('.chip').forEach((chip) => chip.setAttribute('aria-pressed', 'false'));
  const defaultChip = controls.querySelector('[data-filter="all"]');
  if (defaultChip) {
    defaultChip.setAttribute('aria-pressed', 'true');
  }

  const categories = Array.from(new Set(timeline.map((item) => item.category)));

  categories.forEach((category) => {
    const button = document.createElement('button');
    button.className = 'chip';
    button.dataset.filter = category;
    button.textContent = category;
    button.setAttribute('aria-pressed', 'false');
    controls.appendChild(button);
  });

  controls.addEventListener('click', (event) => {
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
  });
}

function renderAchievements(achievements) {
  const container = document.querySelector('.achievements');
  container.innerHTML = '';

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

    container.appendChild(card);
  });
}

function renderSkills(skills) {
  const container = document.querySelector('.skills');
  container.innerHTML = '';

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

    container.appendChild(skillElement);
  });
}

function renderToolkit(toolkit) {
  const container = document.querySelector('.toolkit');
  container.innerHTML = '';

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

    container.appendChild(card);
  });
}

function setupPromptShuffle(prompts) {
  const button = document.querySelector('.narrative__shuffle');
  button.addEventListener('click', () => {
    const order = shuffle([...prompts]);
    state.currentPromptIndex = (state.currentPromptIndex + 1) % order.length;
    document.querySelector('.narrative__prompt').textContent = order[state.currentPromptIndex];
  });
}

function setupModal(achievements) {
  const modal = document.querySelector('.modal');
  const closeButton = modal.querySelector('.modal__close');
  const content = modal.querySelector('.modal__content');

  document.body.addEventListener('click', (event) => {
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
  });

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

  toggle.addEventListener('click', () => {
    const isLight = root.classList.toggle('light');
    toggle.setAttribute('aria-pressed', String(isLight));
  });

  prefersLight.addEventListener('change', (event) => setTheme(event.matches));
}

function showStatus(message) {
  const status = document.querySelector('.hero__status');
  if (!status) return;

  // textContent, not innerHTML: error messages can carry markup from a failed response body.
  status.textContent = message;
  status.hidden = false;
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
  // Bound before the data load so the page stays usable even if the fetch fails.
  renderSection('theme toggle', setupThemeToggle);

  let data;
  try {
    data = await loadData();
  } catch (error) {
    showStatus(`${error.message}. Please refresh to try again.`);
    return;
  }

  const sections = [
    ['hero', () => renderHero(data.profile)],
    [
      'narrative',
      () => {
        renderNarrative(data.profile);
        setupPromptShuffle(data.profile.prompts);
      }
    ],
    ['signals', () => renderSignals(data.signals)],
    [
      'timeline',
      () => {
        renderTimeline(data.timeline, state.activeFilter);
        renderFilters(data.timeline);
      }
    ],
    [
      'achievements',
      () => {
        renderAchievements(data.achievements);
        setupModal(data.achievements);
      }
    ],
    ['skills', () => renderSkills(data.skills)],
    ['toolkit', () => renderToolkit(data.toolkit)]
  ];

  const failed = sections
    .filter(([label, render]) => !renderSection(label, render))
    .map(([label]) => label);

  if (failed.length) {
    showStatus(
      `Some sections could not be displayed: ${failed.join(', ')}. The rest of this page is unaffected.`
    );
  }
}

window.addEventListener('DOMContentLoaded', init);
