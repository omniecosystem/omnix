// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix

// Main-thread-owned permission continuation. Distinct process-lifetime codes
// prevent a late Android result from completing a newer host request.
internal class PendingPermissionAction private constructor(
    val requestCode: Int,
    private var proceed: (() -> Unit)?,
    private var refuse: (() -> Unit)?,
) {
    fun complete(code: Int): Boolean {
        if (code != requestCode) return false
        val action = proceed
        proceed = null
        refuse = null
        action?.invoke()
        return true
    }

    fun cancel() {
        val action = refuse
        proceed = null
        refuse = null
        action?.invoke()
    }

    companion object {
        // Activity request codes use the lower 16 bits. Never wrap and reuse a
        // code whose late result could still be delivered to another host.
        private var nextCode = 3401

        fun create(proceed: () -> Unit, refuse: () -> Unit): PendingPermissionAction? {
            if (nextCode > 65535) return null
            return PendingPermissionAction(nextCode++, proceed, refuse)
        }
    }
}
