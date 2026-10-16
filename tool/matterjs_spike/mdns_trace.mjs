// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
// Fixture diagnostics only. Observe existing sockets; never open a listener.
import { networkInterfaces } from "node:os";
import { DnsCodec } from "@matter/main";
import { interfaceNameForZone } from "./windows_interfaces.mjs";
export { interfaceNameForZone } from "./windows_interfaces.mjs";

export function traceMdns(network, { normalizeInterfaces = false, log = console.log } = {}) {
  const originalCreate = network.createUdpSocket.bind(network);
  let remaining = 200;
  const counts = { rxQueries: 0, rxResponses: 0, txResponses: 0 };
  function describe(data) {
    try {
      const decoded = DnsCodec.decode(data);
      if (!decoded) return;
      const names = [...(decoded.queries ?? []), ...(decoded.answers ?? []),
        ...(decoded.additionalRecords ?? [])].map(record => record.name);
      if (!names.some(name => name.toLowerCase().includes("_matter"))) return;
      return { response: (decoded.messageType & 0x8000) !== 0,
        names: [...new Set(names)].slice(0, 8).map(name => name.slice(0, 128)) };
    } catch { /* Trace failures must never alter the SDK callback. */ }
  }
  function emit(record) {
    if (remaining-- > 0) log(`MDNS_TRACE ${JSON.stringify(record)}`);
  }
  network.createUdpSocket = async options => {
    const socket = await originalCreate(options);
    if (options.listeningPort !== 5353) return socket;
    const originalReceive = socket.onData.bind(socket);
    socket.onData = listener => originalReceive((intf, peer, port, data) => {
      const effective = normalizeInterfaces && process.platform === "win32" && intf
        ? interfaceNameForZone(intf, networkInterfaces()) : intf;
      const message = describe(data);
      if (message) {
        counts[message.response ? "rxResponses" : "rxQueries"]++;
        // Ignore response chatter (including the fixture's own announcements)
        // in the log, but retain totals. Focus the bounded trace on queries.
        if (!message.response) emit({ direction: "RX", peer, port, interface: intf,
          effectiveInterface: effective, interfaceRecognized: !!network.getIpMac(intf), ...message });
      }
      listener(effective, peer, port, data);
    });
    const originalSend = socket.send.bind(socket);
    socket.send = async (host, port, data) => {
      const message = describe(data);
      try {
        await originalSend(host, port, data);
        if (message) {
          if (message.response) counts.txResponses++;
          emit({ direction: "TX_ACCEPTED", host, port, interface: options.netInterface, ...message });
        }
      } catch (error) {
        if (message) emit({ direction: "TX_FAILED", host, port, error: String(error) });
        throw error;
      }
    };
    return socket;
  };
  return () => log(`MDNS_TRACE_SUMMARY ${JSON.stringify(counts)}`);
}
