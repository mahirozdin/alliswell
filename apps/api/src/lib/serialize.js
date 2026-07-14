/** Null-safe DATETIME(3) → ISO-8601 string (mysql2 hands us Date objects). */
export function toIso(value) {
  return value == null ? null : new Date(value).toISOString();
}
