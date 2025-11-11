export function formatStatValue(value) {
  if (typeof value === 'number' && value >= 1000) {
    return `${(value / 1000).toFixed(1)}k`;
  }
  return String(value);
}
