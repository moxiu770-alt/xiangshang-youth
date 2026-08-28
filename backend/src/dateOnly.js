export function dateOnlyText(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'string') {
    const text = value.slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : null;
  }
  if (value instanceof Date && Number.isFinite(value.valueOf())) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  return null;
}
