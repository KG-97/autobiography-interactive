export function formatStatValue(value) {
  if (typeof value !== 'number') {
    return String(value);
  }

  const thresholds = [
    { limit: 1_000_000_000, suffix: 'b' },
    { limit: 1_000_000, suffix: 'm' },
    { limit: 1_000, suffix: 'k' }
  ];

  const absoluteValue = Math.abs(value);

  for (const { limit, suffix } of thresholds) {
    if (absoluteValue >= limit) {
      const formatted = (value / limit).toFixed(1).replace(/\.0$/, '');
      return `${formatted}${suffix}`;
    }
  }

  return String(value);
}
