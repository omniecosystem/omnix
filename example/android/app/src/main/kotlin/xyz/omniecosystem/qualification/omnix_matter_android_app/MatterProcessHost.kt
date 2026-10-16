// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import chip.devicecontroller.ChipDeviceController
import chip.platform.*
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

// Qualification host only. In the pinned SDK, ChipDeviceController.close()
// releases Bluetooth state; native controller deletion is private/finalizer-owned.
// Retain one owner per process, never one per Activity or Flutter engine.
internal object MatterProcessHost {
    private var platform: AndroidChipPlatform? = null
    private var qualification: MatterQualification? = null
    private val failures = MatterFailureGate()
    private val worker = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(4),
        ThreadPoolExecutor.AbortPolicy()
    )

    fun submit(context: Context, onFailure: (Throwable) -> Unit, operation: (MatterQualification) -> Unit) {
        checkHealthy()
        val app = context.applicationContext
        worker.execute {
            try {
                failures.run {
                    initializePlatform(app)
                    val owner = qualification ?: MatterQualification(app).also { qualification = it }
                    operation(owner)
                }
            } catch (error: Throwable) {
                onFailure(error)
            }
        }
    }

    fun checkHealthy() = failures.checkHealthy()

    fun quarantine() = failures.quarantine()

    private fun initializePlatform(context: Context) {
        if (platform != null) return
        ChipDeviceController.loadJni()
        val ble = AndroidBleManager(context)
        val owner = AndroidChipPlatform(
            ble, null, PreferencesKeyValueStoreManager(context),
            PreferencesConfigurationManager(context), NsdManagerServiceResolver(context),
            NsdManagerServiceBrowser(context), ChipMdnsCallbackImpl(),
            DiagnosticDataProviderImpl(context)
        )
        ble.setAndroidChipPlatform(owner)
        platform = owner
    }
}
