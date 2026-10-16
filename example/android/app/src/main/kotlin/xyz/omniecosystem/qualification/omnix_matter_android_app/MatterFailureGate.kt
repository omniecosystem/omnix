// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.qualification.omnix_matter_android_app

import java.util.concurrent.atomic.AtomicBoolean

// Shared by the serialized SDK worker and bridge callers observing timeouts.
// Quarantine rejects later work; it neither interrupts nor frees active callbacks.
internal class MatterFailureGate {
    private val blocked = AtomicBoolean(false)

    fun checkHealthy() {
        check(!blocked.get()) { "Matter host requires process restart after failure" }
    }

    fun quarantine() {
        blocked.set(true)
    }

    fun <T> run(operation: () -> T): T {
        checkHealthy()
        try {
            return operation()
        } catch (error: Throwable) {
            quarantine()
            throw error
        }
    }
}
