import { ulid } from 'ulid';

/**
 * Generates a new entity id. All AllisWell ids are ULIDs stored as CHAR(26)
 * (lexicographically sortable by creation time — see ADR-0004).
 */
export function newId() {
  return ulid();
}
