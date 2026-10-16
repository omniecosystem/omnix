// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { normalizeWindowsInterfaces } from "./windows_interfaces.mjs";

// Arm before loading the SDK too: module initialization is part of the test.
const control = process.argv.includes("--control");
const deadline = setTimeout(() => {
  console.error("FAIL: Matter experiment exceeded its deadline");
  process.exit(1);
}, control ? 180_000 : 90_000);
deadline.unref();
console.log("Loading Matter.js controller SDK...");
const { Environment, StorageService, ServerNode, Endpoint, Network } = await import("@matter/main");
const { CommissioningController } = await import("@project-chip/matter.js");
const { OnOffLightDevice } = await import("@matter/main/devices/on-off-light");
const { OnOffClient } = await import("@matter/main/behaviors/on-off");

// Own a fresh test fabric; never load the host application's credentials.
const storage = await mkdtemp(join(tmpdir(), "omnix-matterjs-spike-"));
const environment = Environment.default;
normalizeWindowsInterfaces(environment.get(Network));
environment.vars.set("storage.path", storage);
assert.equal(resolve(environment.get(StorageService).location), resolve(storage));
const createController = () => new CommissioningController({
  environment: { environment, id: "isolated-controller" },
  adminFabricLabel: "Omnix controller experiment",
  autoConnect: false,
  listeningAddressIpv4: "127.0.0.1",
  listeningAddressIpv6: "::1",
});
let controller = createController();

let light;
try {
  if (control) {
    light = await ServerNode.create({
      id: "isolated-software-light",
      environment,
      commissioning: { passcode: 20202021, discriminator: 3840 },
      // Operational mDNS advertises LAN addresses, so the simulator must accept
      // those addresses too. Commissioning still targets our explicit local port.
      network: { port: 5542 },
    });
    await light.add(new Endpoint(OnOffLightDevice, { id: "light", onOff: { onOff: false } }));
    await light.start();
    console.log("Disposable software light started on local port 5542 (LAN listener).");
  }
  await controller.start();
  assert.equal(controller.getCommissionedNodes().length, 0);
  console.log("PASS: isolated Matter.js controller started; no devices commissioned.");
  if (control) {
    const nodeId = await controller.commissionNode({
      commissioning: { regulatoryCountryCode: "XX", regulatoryLocation: 2 },
      discovery: {
        knownAddress: { ip: "127.0.0.1", port: 5542, type: "udp" },
        identifierData: { longDiscriminator: 3840 },
        discoveryCapabilities: { ble: false },
      },
      passcode: 20202021,
    });
    const peer = await controller.getNode(nodeId);
    if (!peer.isConnected) await peer.connect();
    const endpoint = peer.parts.get(1);
    assert.ok(endpoint, "commissioned device must expose its light endpoint");
    const commands = endpoint.commandsOf(OnOffClient);
    await commands.on();
    assert.equal((await endpoint.getStateOf(OnOffClient)).onOff, true);
    await commands.off();
    assert.equal((await endpoint.getStateOf(OnOffClient)).onOff, false);
    console.log("PASS: commissioned software light; remote On/Off commands and reads succeeded.");
    await controller.close();
    controller = createController();
    await controller.start();
    assert.ok(controller.getCommissionedNodes().some(id => id === nodeId));
    const restored = await controller.getNode(nodeId);
    if (!restored.isConnected) await restored.connect();
    const restoredLight = restored.parts.get(1);
    assert.equal((await restoredLight.getStateOf(OnOffClient)).onOff, false);
    await restoredLight.commandsOf(OnOffClient).on();
    assert.equal((await restoredLight.getStateOf(OnOffClient)).onOff, true);
    await restoredLight.commandsOf(OnOffClient).off();
    console.log("PASS: controller reopened its stored fabric and controlled the paired light without recommissioning.");
  }
} finally {
  try { await controller.close(); } finally { await light?.close(); }
}
console.log("PASS: controller shutdown completed.");
console.log(`Test-only credentials retained at: ${storage}`);
// Leave the watchdog armed until natural exit: lingering SDK handles fail the test.
