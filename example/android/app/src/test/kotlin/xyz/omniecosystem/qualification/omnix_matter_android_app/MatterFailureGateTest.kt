// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.qualification.omnix_matter_android_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class MatterFailureGateTest {
    @Test
    fun successfulOperationsKeepTheOwnerUsable() {
        val gate = MatterFailureGate()
        assertEquals("first", gate.run { "first" })
        assertEquals("second", gate.run { "second" })
        gate.checkHealthy()
    }

    @Test
    fun failurePropagatesAndPreventsLaterOperations() {
        val gate = MatterFailureGate()
        val original = IllegalStateException("Synthetic native failure")
        assertSame(original, assertThrows(IllegalStateException::class.java) {
            gate.run<Unit> { throw original }
        })
        var dispatched = false
        assertThrows(IllegalStateException::class.java) {
            gate.run { dispatched = true }
        }
        assertFalse(dispatched)
    }

    @Test
    fun timeoutQuarantinesTheOwnerWithoutAutomaticRetry() {
        val gate = MatterFailureGate()
        var attempts = 0
        assertThrows(TimeoutException::class.java) {
            gate.run { attempts++; throw TimeoutException("Synthetic timeout") }
        }
        assertThrows(IllegalStateException::class.java) {
            gate.run { attempts++ }
        }
        assertEquals(1, attempts)
    }

    @Test
    fun callerQuarantineRejectsWorkThatHasNotStarted() {
        val gate = MatterFailureGate()
        gate.quarantine()
        gate.quarantine()
        var dispatched = false
        assertThrows(IllegalStateException::class.java) {
            gate.run { dispatched = true }
        }
        assertFalse(dispatched)
    }

    @Test
    fun quarantineDoesNotInterruptAnAlreadyRunningAction() {
        val gate = MatterFailureGate()
        val started = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val completions = AtomicInteger()
        val worker = Thread {
            gate.run {
                started.countDown()
                if (finish.await(5, TimeUnit.SECONDS)) completions.incrementAndGet()
            }
        }
        worker.start()
        try {
            assertTrue(started.await(5, TimeUnit.SECONDS))
            gate.quarantine()
            assertThrows(IllegalStateException::class.java) { gate.checkHealthy() }
            finish.countDown()
            worker.join(5000)
            assertFalse(worker.isAlive)
            assertEquals(1, completions.get())
        } finally {
            finish.countDown()
            worker.join(5000)
        }
    }
}
