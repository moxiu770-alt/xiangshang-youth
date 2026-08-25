/**
 * Calendar age helpers shared by all age-for-sex reference models.
 * Birthday values are date-only strings, never instants.  The API uses the
 * China business calendar so a request around midnight cannot drift from a
 * native client into a different reference month.
 */
export const BUSINESS_TIME_ZONE = 'Asia/Shanghai';

export function ageMonthsFromBirthDate(birthDate, now = new Date()) {
  // node-postgres represents SQL DATE as a JavaScript Date in many runtime
  // configurations.  Treat that value as a China date, not as an instant
  // formatted in the server timezone; otherwise 2017-05-12 becomes the
  // previous day in UTC and valid age-based scoring is silently unavailable.
  const raw = birthDate instanceof Date
    ? new Intl.DateTimeFormat('en-CA', { timeZone: BUSINESS_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' })
      .formatToParts(birthDate)
      .reduce((result, part) => part.type === 'year' || part.type === 'month' || part.type === 'day' ? `${result}${part.value}` : result, '')
      .replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3')
    : String(birthDate || '').trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return null;
  const birthYear = Number(match[1]);
  const birthMonth = Number(match[2]);
  const birthDay = Number(match[3]);
  const parsed = new Date(Date.UTC(birthYear, birthMonth - 1, birthDay));
  if (parsed.getUTCFullYear() !== birthYear || parsed.getUTCMonth() !== birthMonth - 1 || parsed.getUTCDate() !== birthDay) return null;

  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: BUSINESS_TIME_ZONE,
    year: 'numeric', month: '2-digit', day: '2-digit'
  }).formatToParts(now).reduce((result, part) => {
    if (part.type === 'year' || part.type === 'month' || part.type === 'day') result[part.type] = Number(part.value);
    return result;
  }, {});
  const nowYear = parts.year;
  const nowMonth = parts.month;
  const nowDay = parts.day;
  if (![nowYear, nowMonth, nowDay].every(Number.isInteger)) return null;

  const months = (nowYear - birthYear) * 12 + nowMonth - birthMonth - (nowDay < birthDay ? 1 : 0);
  return months >= 0 && months <= 240 ? months : null;
}
