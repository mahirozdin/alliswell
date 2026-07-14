/**
 * Wall-clock ↔ UTC helpers for alarm math (OPH-035). Pure Intl, no timezone
 * libraries — Node's ICU data is the source of truth.
 */

function wallClockParts(instant, timeZone) {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts = Object.fromEntries(fmt.formatToParts(instant).map((p) => [p.type, p.value]));
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}

/**
 * The UTC instant at which `timeZone` shows the given wall-clock time.
 * Two correction passes make it DST-transition safe.
 */
export function zonedWallTimeToUtc({ year, month, day, hour = 0, minute = 0 }, timeZone) {
  const target = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  let ts = target;
  for (let i = 0; i < 2; i += 1) {
    const wall = wallClockParts(new Date(ts), timeZone);
    const wallAsUtc = Date.UTC(
      wall.year,
      wall.month - 1,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    );
    ts += target - wallAsUtc;
  }
  return new Date(ts);
}

/** Tomorrow at `hour`:00 on the wall clock of `timeZone`, relative to `from`. */
export function nextMorningIn(timeZone, from = new Date(), hour = 9) {
  const today = wallClockParts(from, timeZone);
  // +1 calendar day on the wall date; Date.UTC normalizes month/year overflow.
  const next = new Date(Date.UTC(today.year, today.month - 1, today.day + 1));
  return zonedWallTimeToUtc(
    {
      year: next.getUTCFullYear(),
      month: next.getUTCMonth() + 1,
      day: next.getUTCDate(),
      hour,
    },
    timeZone,
  );
}
