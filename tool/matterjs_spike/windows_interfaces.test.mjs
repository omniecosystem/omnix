import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeWindowsInterfaces } from "./windows_interfaces.mjs";

test("Windows correction is idempotent and preserves subscription and payload", async () => {
  let receive;
  let opens = 0;
  const subscription = {};
  const socket = { onData(fn) { receive = fn; return subscription; } };
  const network = { async createUdpSocket() { opens++; return socket; } };
  const options = { platform: "win32", interfaces: () => ({ "Wi-Fi": [{ scopeid: 21 }] }) };
  normalizeWindowsInterfaces(network, options);
  const create = network.createUdpSocket;
  normalizeWindowsInterfaces(network, options);
  assert.equal(network.createUdpSocket, create);
  const wrapped = await network.createUdpSocket({ listeningPort: 5353 });
  let args;
  assert.equal(wrapped.onData((...values) => { args = values; }), subscription);
  const payload = new Uint8Array([1]);
  receive("21", "192.168.1.123", 5353, payload);
  assert.deepEqual(args, ["Wi-Fi", "192.168.1.123", 5353, payload]);
  assert.equal(args[3], payload);
  assert.equal(opens, 1);
});

test("other platforms and non-mDNS sockets are unchanged", async () => {
  const socket = { onData() {} };
  const network = { async createUdpSocket() { return socket; } };
  const create = network.createUdpSocket;
  normalizeWindowsInterfaces(network, { platform: "linux" });
  assert.equal(network.createUdpSocket, create);
  const receive = socket.onData;
  normalizeWindowsInterfaces(network, { platform: "win32" });
  assert.equal(await network.createUdpSocket({ listeningPort: 5540 }), socket);
  assert.equal(socket.onData, receive);
});
