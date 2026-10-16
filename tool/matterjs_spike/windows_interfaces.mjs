// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import { networkInterfaces } from "node:os";

export function interfaceNameForZone(zone, interfaces) {
  if (Object.hasOwn(interfaces, zone)) return zone;
  const names = Object.entries(interfaces).filter(([, addresses]) =>
    addresses?.some(address => address.scopeid > 0 && String(address.scopeid) === zone),
  ).map(([name]) => name);
  return names.length === 1 ? names[0] : zone;
}

const installed = new WeakSet();

// Apply before SDK socket creation. Preserve socket ownership, subscriptions,
// payloads and send behavior; only normalize Windows mDNS receive metadata.
export function normalizeWindowsInterfaces(network, {
  platform = process.platform, interfaces = networkInterfaces,
} = {}) {
  if (platform !== "win32" || installed.has(network)) return;
  installed.add(network);
  const create = network.createUdpSocket.bind(network);
  network.createUdpSocket = async options => {
    const socket = await create(options);
    if (options.listeningPort !== 5353) return socket;
    const onData = socket.onData.bind(socket);
    socket.onData = listener => onData((intf, peer, port, data) =>
      listener(intf ? interfaceNameForZone(intf, interfaces()) : intf, peer, port, data));
    return socket;
  };
}
