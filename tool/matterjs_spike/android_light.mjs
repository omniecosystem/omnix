// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
// Disposable LAN fixture; never a production device or credential store.
import { mkdtemp } from "node:fs/promises";
import { tmpdir, networkInterfaces } from "node:os";
import { join } from "node:path";
import { Environment, ServerNode, Endpoint, Network } from "@matter/main";
import { traceMdns } from "./mdns_trace.mjs";
import { OnOffLightDevice } from "@matter/main/devices/on-off-light";

const address = process.argv[2];
if (!Object.values(networkInterfaces()).flat().some(nic => nic?.address === address && !nic.internal)) {
  throw new Error("Supply this host's literal LAN address, not localhost or a remote address");
}
const storage = await mkdtemp(join(tmpdir(), "omnix-android-light-"));
const environment = Environment.default;
environment.vars.set("storage.path", storage);
const normalizeInterfaces = process.argv.includes("--normalize-windows-interfaces");
const trace = process.argv.includes("--trace-mdns") || normalizeInterfaces
  ? traceMdns(environment.get(Network), { normalizeInterfaces }) : undefined;
if (normalizeInterfaces) console.log("Qualification-only Windows interface normalization enabled.");
const light = await ServerNode.create({
  id: "android-qualification-light",
  environment,
  commissioning: { passcode: 20202021, discriminator: 3840 },
  network: { port: 5542 },
});
await light.add(new Endpoint(OnOffLightDevice, { id: "light", onOff: { onOff: false } }));
await light.start();
console.log(`READY: software light at ${address}:5542; endpoint 1`);
console.log("Test PAA NoVID only. No attestation bypass. Keep running across the Android process restart.");
console.log(`Disposable fixture state: ${storage}`);
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  await light.close();
  trace?.();
  console.log("Software light stopped; test state retained for diagnosis.");
}
process.once("SIGINT", () => { void stop(); });
process.once("SIGTERM", () => { void stop(); });
// Never leave an unattended fixture running indefinitely.
setTimeout(() => { void stop(); }, 20 * 60_000).unref();
