# Platform support

Omnix is designed for Android, iOS, Windows, macOS, Linux, and web. Support is
reported conservatively: a platform becomes **verified** only after native
bridge build and integration tests run for it in continuous integration.

| Platform | Current status | Priority |
| --- | --- | --- |
| Android | Scaffolded | Primary |
| Windows | Scaffolded | Primary |
| iOS | Scaffolded | Secondary |
| macOS | Scaffolded | Secondary |
| Linux | Scaffolded | Secondary |
| Web/WASM | Scaffolded, separate FRB web build required | Experimental |

Primary priority reflects initial verification capacity, not a permanent API
or architecture limitation. Platform-specific functionality must sit behind
an Omnix contract and expose capability detection rather than silently
changing behavior.
