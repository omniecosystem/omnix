# Official SDK build and controller lifecycle qualification

Development-only Linux SDK environment. Unlike `matter_cpp_contract`, this
builds the wrapper against actual official SDK headers and controller libraries.
The GN linker rejects unresolved symbols, checks the exported ABI getter, and
a native load check validates the complete versioned function table.
It also builds a disposable operational controller host with the official SDK
test issuer and volatile storage. A 90-second bounded run starts the real event
loop, verifies scheduled callback dispatch, attaches/closes the shim eight times
under the real stack lock, checks
owner retention, joins the event loop, and shuts the SDK down. No device is
commissioned or commanded; fabric persistence and Android remain unqualified.

From the Omnix repository root on Windows with Docker Desktop/Linux containers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\test_matter_cpp_sdk.ps1 -SourcePath C:/path/to/connectedhomeip
```

The supplied checkout must match revision
`0fa0eb338e20dad90b269149581c693a970a03cc`. It is mounted read-only and cloned
into Docker volume `omnix-matter-sdk-qualification`; wrapper/build inputs are
also mounted read-only. SDK submodules use the official Linux/shallow selector.
The SDK's own bootstrap config pins its development tools and Python requirements.
The supported bootstrap configuration override uses upstream C++ build Python
requirements, not the separate Python agent/test packages and their cloud-tool
dependencies. Its GN/Ninja build compiles the C++ SDK; this is not an ad-hoc
compiler invocation.

The native-only environment uses Pigweed's supported `PW_ACTIVATE_SKIP_CHECKS`
switch: the general multitool doctor imports optional Python plugins outside
this configuration. Bootstrap failures are still fatal, and the script checks
GN, Ninja, Clang and the required Python generator imports before building.

The initial image/environment may consume several gigabytes and download Linux
packages, SDK submodules and development tools. The image and volume are retained
for retry and diagnosis; the temporary build container removes itself on exit.
No unrelated containers, volumes, installed applications, models or databases
are stopped or deleted. Nothing is uploaded to a remote repository.

The standalone GN project uses upstream example dependency overrides, with its
own SDK/build roots. Both `chip_enable_ble` (platform services) and
`chip_config_network_layer_ble` (transport) are explicitly disabled: disabling
only the former leaves the controller requiring a missing BLE layer. Wi-Fi
provisioning and Thread are also disabled for this initial on-network build. These disabled
features must not be mistaken for full commissioning/platform coverage.

The SDK may create configuration files under `/tmp` inside the disposable
container and open network sockets on its Docker bridge. No Windows host
network mode, privileged container, host fabric directory or consumer app data
is used. Test credentials are volatile, not production credentials. Fatal
startup failures exit the test process without invoking global SDK destructors
on an incompletely initialized stack; normal success tests orderly teardown.

Passing these checks is narrower than running a long-lived commissioner against
a software device. Outstanding-command callbacks, durable credentials, device
readback, restart and mobile lifecycle remain further qualification work.
