// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix.nexus

// Qualification integration: this symbol is in the *same* FRB bridge library.
// Never load a second copy with a separate Rust registration registry.
// The owner must implement hostSetOnOff(String, Int, Boolean): Unit and
// hostReadOnOff(String, Int): Boolean; registration validates their JVM signatures.
object MatterHostRegistration {
    external fun register(owner: Any): Boolean
}
