// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

// Global JNI reference retains only application context and the process owner.
// Calls originate on FRB workers, never the SDK worker or UI thread.
class RegisteredMatterHost(context: Context) {
    private val context = context.applicationContext
    private val blocked = AtomicBoolean(false)

    private fun <T> dispatch(operation: (MatterQualification) -> T): T {
        check(!blocked.get()) { "Matter host needs process restart after failure" }
        val answer = CompletableFuture<T>()
        try {
            MatterProcessHost.submit(context, { answer.completeExceptionally(it) }) { owner ->
                if (blocked.get()) {
                    answer.completeExceptionally(IllegalStateException("Matter host blocked"))
                } else {
                    try { answer.complete(operation(owner)) }
                    catch (error: Throwable) { answer.completeExceptionally(error) }
                }
            }
            // SDK operations bound connection+response waits at 60+30 seconds.
            return answer.get(100, TimeUnit.SECONDS)
        } catch (error: Throwable) {
            blocked.set(true)
            // Do not cancel/drop SDK callbacks or delete their process owner.
            throw error
        }
    }

    fun hostSetOnOff(node: String, endpoint: Int, on: Boolean) {
        dispatch { it.hostSetOnOff(node, endpoint, on) }
    }

    fun hostReadOnOff(node: String, endpoint: Int): Boolean =
        dispatch { it.hostReadOnOff(node, endpoint) }
}
