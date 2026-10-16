# Windows operational discovery diagnosis

Qualified on 8 October 2026 with Matter.js 0.17.9, Node 24.19.0,
the isolated Android SDK/JNI host, and both devices on the same 2G Wi-Fi.

## Cause identified in the Windows fixture

The fixture's existing UDP sockets receive the phone's IPv4 and IPv6 queries
for `_matter._tcp.local`. This rules out complete blocking of those queries
between the phone and the Windows application in this experiment.

The pinned Node implementation reports the source interface as the Windows
IPv6 scope ID string (`"21"` on this host). `MdnsServer` asks
`network.getIpMac(incomingMessage.sourceIntf)` for its response records, while
`NodeJsNetwork.getIpMac()` indexes `os.networkInterfaces()` by interface name
(`"Wi-Fi"`), not by numeric scope ID. The lookup returns undefined and the
responder returns without replying. Its unsolicited announcements still work,
which explains why initial discovery can work but later queries fail.

Source paths inside the pinned published packages:

- `@matter/nodejs/src/net/NodeJsUdpSocket.ts`: `onData()` supplies the zone.
- `@matter/nodejs/src/net/NodeJsNetwork.ts`: `getNetInterfaceForIp()` and
  `getIpMac()` use different interface representations.
- `@matter/protocol/src/mdns/MdnsServer.ts`: interface record generation and
  the empty-record early return in `#handleMessage()`.

This identifies a responder portability defect, not a defect in Matter's
wire protocol, Android attestation, or Rust cryptographic identity.

## Reproduce and qualify locally

From this directory, start a trace-only baseline:

```powershell
node android_light.mjs 192.168.1.129 --trace-mdns
```

Trace lines for the phone show `interface: "21"`,
`interfaceRecognized: false`, and `response: false`. Inspect the Android
host's runner commands in [its guide](../matter_android_app/README.md).
An instrumented baseline commissioning attempt also hit CASE error `0xC9`
(`No shared trusted root`); do not present that attempt as a clean discovery
timeout benchmark. The interface mismatch is independently shown by received
queries and source inspection.

Stop that fixture and start a fresh one with the explicit experimental adapter:

```powershell
node android_light.mjs 192.168.1.129 --trace-mdns --normalize-windows-interfaces
```

Commission this new disposable fixture once, then run control twice without
`-Commission`, keeping the same fixture process alive. Both Android process
restarts passed: restored fabric, DNS-SD resolution, CASE, On/Off and readback.
Restoration asserts zero attestation lookups so it cannot quietly pair again.
An independent Android NSD probe also passed after a further process restart,
finding the stored fabric's operational service within six seconds.

The adapter only translates incoming scope IDs to unique local interface
names. Unknown or ambiguous mappings are left unchanged. It does not open
another listener, inject a device IP, modify upstream files, change certificate
verification, or alter firewall/router settings. It is opt-in fixture code,
not a shipped Nexus backend. `TX_ACCEPTED` means the OS accepted a send; the
Android resolver/control tests provide the separate receipt/interoperability
evidence. Logs are bounded and exclude DNS TXT values and credential bytes.

Run its regression checks:

```powershell
node --test mdns_trace.test.mjs
```

## Next boundary

An upstream-compatible fix belongs in the Windows Matter.js platform adapter;
do not compensate by lengthening Android browse timeouts or disabling trust.
No upstream issue or PR has been published by this experiment. Preserve this
regression when choosing/updating the packaged Windows backend. Android's
deterministic native ownership, reproducible SDK provenance and the common
Nexus host-adapter integration remain separate unfinished gates.
