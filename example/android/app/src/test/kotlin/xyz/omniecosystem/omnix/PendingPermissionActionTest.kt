// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix

import org.junit.Assert.*
import org.junit.Test

class PendingPermissionActionTest {
    @Test
    fun cancellationRefusesOnceAndLateResultsCannotEnqueueWork() {
        var enqueues = 0
        var refusals = 0
        val request = PendingPermissionAction.create({ enqueues++ }, { refusals++ })!!
        request.cancel()
        request.cancel()
        assertTrue(request.complete(request.requestCode))
        assertEquals(0, enqueues)
        assertEquals(1, refusals)
    }

    @Test
    fun successfulResultCompletesOnlyOnce() {
        var enqueues = 0
        var refusals = 0
        val request = PendingPermissionAction.create({ enqueues++ }, { refusals++ })!!
        assertTrue(request.complete(request.requestCode))
        assertTrue(request.complete(request.requestCode))
        request.cancel()
        assertEquals(1, enqueues)
        assertEquals(0, refusals)
    }

    @Test
    fun lateResultCannotCompleteANewerRequest() {
        var enqueues = 0
        var refusals = 0
        val previous = PendingPermissionAction.create({}, {})!!
        previous.cancel()
        val current = PendingPermissionAction.create({ enqueues++ }, { refusals++ })!!
        assertNotEquals(previous.requestCode, current.requestCode)
        assertFalse(current.complete(previous.requestCode))
        assertEquals(0, enqueues)
        assertEquals(0, refusals)
        assertTrue(current.complete(current.requestCode))
        assertEquals(1, enqueues)
    }

    @Test
    fun callbacksMayReenterWithoutCompletingOrRefusingTwice() {
        var calls = 0
        lateinit var request: PendingPermissionAction
        request = PendingPermissionAction.create({
            calls++
            request.cancel()
            request.complete(request.requestCode)
        }, { fail("Completed requests cannot be refused.") })!!
        request.complete(request.requestCode)
        assertEquals(1, calls)
    }
}
