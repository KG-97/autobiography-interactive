export function formatStatValue(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return String(value);
  }

  const suffixes = ['', 'k', 'm', 'b'];
  let scaled = value;
  let suffixIndex = 0;

  while (Math.abs(scaled) >= 1000 && suffixIndex < suffixes.length - 1) {
    scaled /= 1000;
    suffixIndex += 1;
  }

  let rounded = Number(scaled.toFixed(1));

  while (Math.abs(rounded) >= 1000 && suffixIndex < suffixes.length - 1) {
    scaled = rounded / 1000;
    suffixIndex += 1;
    rounded = Number(scaled.toFixed(1));
  }

  const formatted = Number.isInteger(rounded) ? rounded.toString() : rounded.toFixed(1).replace(/\.0$/, '');
  return `${formatted}${suffixes[suffixIndex]}`;
}
