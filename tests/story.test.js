import test from 'node:test';
import assert from 'node:assert/strict';
import story from '../data/story.json' with { type: 'json' };

test('story profile includes prompts and focus areas', () => {
  assert.ok(story.profile.name, 'Profile should include a name');
  assert.ok(Array.isArray(story.profile.prompts), 'Prompts must be an array');
  assert.ok(story.profile.prompts.length >= 3, 'At least three prompts are expected');
  assert.ok(Array.isArray(story.profile.focus), 'Focus must be an array');
});

test('timeline entries include essential fields', () => {
  assert.ok(Array.isArray(story.timeline), 'Timeline must be an array');
  assert.ok(story.timeline.length >= 3, 'Timeline must include multiple entries');

  for (const entry of story.timeline) {
    assert.ok(entry.year, 'Timeline entry should include a year');
    assert.ok(entry.title, 'Timeline entry should include a title');
    assert.ok(entry.category, 'Timeline entry should include a category');
  }
});

test('achievements include detail bullet points', () => {
  assert.ok(Array.isArray(story.achievements), 'Achievements must be an array');
  for (const achievement of story.achievements) {
    assert.ok(achievement.details?.length, 'Achievement should have details');
  }
});
