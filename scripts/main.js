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
  const categories = Array.from(new Set(timeline.map((item) => item.category)));

  categories.forEach((category) => {
    const button = document.createElement('button');
    button.className = 'chip';
    button.dataset.filter = category;
    button.textContent = category;
    controls.appendChild(button);
  });

  controls.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLButtonElement)) return;

    const { filter } = event.target.dataset;
    state.activeFilter = filter;

    controls
      .querySelectorAll('.chip')
      .forEach((chip) => chip.classList.toggle('chip--active', chip.dataset.filter === filter));

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
      <div class="skill__progress">
        <div class="skill__progress-bar" style="transform: scaleX(${skill.progress})"></div>
      </div>
    `;

    container.appendChild(skillElement);
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

async function init() {
  try {
    const data = await loadData();
    renderHero(data.profile);
    renderNarrative(data.profile);
    renderTimeline(data.timeline, state.activeFilter);
    renderFilters(data.timeline);
    renderAchievements(data.achievements);
    renderSkills(data.skills);
    setupPromptShuffle(data.profile.prompts);
    setupModal(data.achievements);
    setupThemeToggle();
  } catch (error) {
    const hero = document.querySelector('.hero__content');
    hero.innerHTML = `<p role="alert">${error.message}. Please refresh to try again.</p>`;
  }
}

window.addEventListener('DOMContentLoaded', init);
