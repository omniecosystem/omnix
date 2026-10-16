package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import chip.devicecontroller.ChipDeviceController
import chip.platform.*
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

// Qualification host only. This SDK exposes no public deterministic native
// delete API. Retain one owner per process, never one per Activity or engine.
internal object MatterProcessHost {
    private var platform: AndroidChipPlatform? = null
    private var qualification: MatterQualification? = null
    private val worker = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(4),
        ThreadPoolExecutor.AbortPolicy()
    )

    fun submit(context: Context, onFailure: (Throwable) -> Unit, operation: (MatterQualification) -> Unit) {
        val app = context.applicationContext
        worker.execute {
            try {
                initializePlatform(app)
                val owner = qualification ?: MatterQualification(app).also { qualification = it }
                operation(owner)
            } catch (error: Throwable) {
                onFailure(error)
            }
        }
    }

    private fun initializePlatform(context: Context) {
        if (platform != null) return
        ChipDeviceController.loadJni()
        val ble = AndroidBleManager(context)
        val owner = AndroidChipPlatform(
            // This LAN-only qualification does not enable NFC commissioning.
            ble, null, PreferencesKeyValueStoreManager(context),
            PreferencesConfigurationManager(context), NsdManagerServiceResolver(context),
            NsdManagerServiceBrowser(context), ChipMdnsCallbackImpl(),
            DiagnosticDataProviderImpl(context)
        )
        ble.setAndroidChipPlatform(owner)
        platform = owner
    }
}
