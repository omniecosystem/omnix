// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

// Global JNI reference retains only application context and the process owner.
// Calls originate on FRB workers, never the SDK worker or UI thread.
// A frontend close releases its Rust lease, not this process-scoped SDK owner.
class RegisteredMatterHost(context: Context) {
    private val context = context.applicationContext

    private fun <T> dispatch(operation: (MatterQualification) -> T): T {
        MatterProcessHost.checkHealthy()
        val answer = CompletableFuture<T>()
        try {
            MatterProcessHost.submit(context, { answer.completeExceptionally(it) }) { owner ->
                // Let the process owner quarantine SDK failures before reporting them.
                answer.complete(operation(owner))
            }
            // SDK operations bound connection+response waits at 60+30 seconds.
            return answer.get(100, TimeUnit.SECONDS)
        } catch (error: Throwable) {
            // A timeout can outlive its caller. Block fixture and bridge work,
            // including queued operations, without dropping callback ownership.
            MatterProcessHost.quarantine()
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
