import { test } from "node:test";
import assert from "node:assert/strict";
import { interfaceNameForZone, traceMdns } from "./mdns_trace.mjs";

const interfaces = { "Wi-Fi": [{ scopeid: 21 }], Tailscale: [{ scopeid: 29 }] };
test("Windows scope ID becomes the interface name required by getIpMac", () => {
  assert.equal(interfaceNameForZone("21", interfaces), "Wi-Fi");
  assert.equal(interfaceNameForZone("29", interfaces), "Tailscale");
});

test("trace mode preserves callbacks and sends without opening extra sockets", async () => {
  let opens = 0;
  let receiver;
  let sent;
  const token = { close: async () => {} };
  const socket = {
    onData(listener) { receiver = listener; return token; },
    async send(...args) { sent = args; },
  };
  const network = {
    async createUdpSocket() { opens++; return socket; },
    getIpMac() { return undefined; },
  };
  traceMdns(network, { log: () => {} });
  const traced = await network.createUdpSocket({ listeningPort: 5353 });
  let received;
  assert.equal(traced.onData((...args) => { received = args; }), token);
  const bytes = new Uint8Array([0]);
  receiver("21", "192.168.1.123", 5353, bytes);
  assert.deepEqual(received, ["21", "192.168.1.123", 5353, bytes]);
  await traced.send("224.0.0.251", 5353, bytes);
  assert.deepEqual(sent, ["224.0.0.251", 5353, bytes]);
  assert.equal(opens, 1);
});
test("names, unknown zones, and ambiguous zones are not rewritten", () => {
  assert.equal(interfaceNameForZone("Wi-Fi", interfaces), "Wi-Fi");
  assert.equal(interfaceNameForZone("77", interfaces), "77");
  assert.equal(interfaceNameForZone("21", { ...interfaces, other: [{ scopeid: 21 }] }), "21");
});
