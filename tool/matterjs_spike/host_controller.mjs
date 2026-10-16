// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
// Qualification-only host. Test fixture selection is mandatory and explicit.
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { normalizeWindowsInterfaces } from "./windows_interfaces.mjs";

const wireWrite = process.stdout.write.bind(process.stdout);
// SDK diagnostics never share the response channel.
process.stdout.write = (...args) => process.stderr.write(...args);
function send(message) { wireWrite(`${JSON.stringify(message)}\n`); }
assert.equal(process.argv[2], "--fixture");
const directory = process.argv[3];
assert.ok(directory && resolve(directory) === directory, "Absolute private test directory required");
const watchdog = setTimeout(() => process.exit(1), 240_000);
watchdog.unref();
const { Environment, ServerNode, Endpoint, Network } = await import("@matter/main");
const { CommissioningController } = await import("@project-chip/matter.js");
const { OnOffLightDevice } = await import("@matter/main/devices/on-off-light");
const { OnOffClient } = await import("@matter/main/behaviors/on-off");
const environment = Environment.default;
environment.vars.set("storage.path", directory);
normalizeWindowsInterfaces(environment.get(Network));
const controller = new CommissioningController({
  environment: { environment, id: "rust-host-controller" }, autoConnect: false,
  adminFabricLabel: "Omnix Rust host qualification",
  listeningAddressIpv4: "127.0.0.1", listeningAddressIpv6: "::1",
});
let light;
try {
  light = await ServerNode.create({ id: "rust-host-light", environment,
    commissioning: { passcode: 20202021, discriminator: 3840 }, network: { port: 5542 } });
  await light.add(new Endpoint(OnOffLightDevice, { id: "light", onOff: { onOff: false } }));
  await light.start();
  await controller.start();
  const nodeId = await controller.commissionNode({
    commissioning: { regulatoryCountryCode: "XX", regulatoryLocation: 2 },
    discovery: { knownAddress: { ip: "127.0.0.1", port: 5542, type: "udp" },
      identifierData: { longDiscriminator: 3840 }, discoveryCapabilities: { ble: false } },
    passcode: 20202021,
  });
  const peer = await controller.getNode(nodeId);
  if (!peer.isConnected) await peer.connect();
  const endpoint = peer.parts.get(1);
  assert.ok(endpoint);
  send({ version: 1, id: 0, kind: "ready", node: nodeId.toString(), endpoint: 1 });
  let buffer = "";
  let lastId = 0;
  let stopped = false;
  for await (const chunk of process.stdin) {
    buffer += chunk.toString("utf8");
    while (buffer.includes("\n")) {
      const boundary = buffer.indexOf("\n");
      assert.ok(Buffer.byteLength(buffer.slice(0, boundary)) <= 4096);
      const request = JSON.parse(buffer.slice(0, boundary));
      buffer = buffer.slice(boundary + 1);
      assert.ok(Number.isSafeInteger(request.id) && request.id > lastId);
      lastId = request.id;
      if (request.op === "shutdown") {
        assert.deepEqual(Object.keys(request).sort(), ["id", "op"]);
        await controller.close();
        await light.close();
        light = undefined;
        stopped = true;
        send({ version: 1, id: request.id, kind: "released" });
        break;
      }
      assert.equal(request.node, nodeId.toString());
      assert.equal(request.endpoint, 1);
      if (request.op === "set") {
        assert.deepEqual(Object.keys(request).sort(), ["endpoint", "id", "node", "on", "op"]);
        assert.equal(typeof request.on, "boolean");
        const commands = endpoint.commandsOf(OnOffClient);
        if (request.on) await commands.on(); else await commands.off();
        send({ version: 1, id: request.id, kind: "ack" });
      } else {
        assert.equal(request.op, "read");
        assert.deepEqual(Object.keys(request).sort(), ["endpoint", "id", "node", "op"]);
        const { onOff } = await endpoint.getStateOf(OnOffClient);
        send({ version: 1, id: request.id, kind: "state", on: onOff });
      }
    }
    assert.ok(Buffer.byteLength(buffer) <= 4096);
    if (stopped) break;
  }
} finally {
  try { await controller.close(); } finally { await light?.close(); }
  clearTimeout(watchdog);
}
