import dns from 'node:dns';
import net from 'node:net';

/**
 * The server-side-request fence (ADR-0047, ADR-0059): one blocklist and one
 * connect-time DNS guard for every fetch whose URL a stranger chose — the
 * OAuth client metadata fetch (`oauth-cimd.js`) and the CalDAV connector
 * (`caldav/client.js`).
 *
 * The check runs inside the socket's `lookup` hook, i.e. AT CONNECT TIME: a
 * name that resolves public once and private the next (DNS rebinding) is
 * refused on the second. An IP literal never reaches `lookup` — callers check
 * those themselves with `isBlockedAddress`.
 */

const blocked = new net.BlockList();
for (const [prefix, bits] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
]) {
  blocked.addSubnet(prefix, bits, 'ipv4');
}
for (const [prefix, bits] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['100::', 64],
  ['2001:db8::', 32],
  ['fc00::', 7],
  ['fe80::', 10],
  ['ff00::', 8],
]) {
  blocked.addSubnet(prefix, bits, 'ipv6');
}

/** True for an address no user-chosen fetch may connect to. */
export function isBlockedAddress(address) {
  const family = net.isIP(address);
  if (family === 0) return true;
  if (family === 6) {
    // An IPv4-mapped IPv6 address is the IPv4 address in disguise.
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
    if (mapped) return blocked.check(mapped[1], 'ipv4');
    return blocked.check(address, 'ipv6');
  }
  return blocked.check(address, 'ipv4');
}

/**
 * A `lookup` for node:http(s) that resolves like `dns.lookup` but refuses —
 * with an Error carrying `blockedCode` — when ANY answer is private/reserved.
 *
 * @param {string} blockedCode e.g. `CIMD_BLOCKED_ADDRESS`, `CALDAV_BLOCKED_ADDRESS`
 */
export function guardedLookup(blockedCode) {
  return function lookup(hostname, options, callback) {
    dns.lookup(hostname, { ...options, all: true }, (err, addresses) => {
      if (err) return callback(err);
      const list = Array.isArray(addresses) ? addresses : [];
      if (list.length === 0 || list.some((entry) => isBlockedAddress(entry.address))) {
        const refused = new Error(`refusing to connect to ${hostname}`);
        refused.code = blockedCode;
        return callback(refused);
      }
      if (options?.all) return callback(null, list);
      return callback(null, list[0].address, list[0].family);
    });
  };
}
