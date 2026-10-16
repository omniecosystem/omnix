package xyz.omniecosystem.qualification.omnix_matter_android_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.RejectedExecutionException

class MainActivity : FlutterActivity() {
    companion object {
        private var bridgeHostRegistered = false
    }
    private var channel: MethodChannel? = null
    @Volatile private var detached = false
    @Volatile private var generation = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detached = false
        generation++
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "omnix/matter-qualification")
        channel!!.setMethodCallHandler { call, result ->
                if (call.method == "registerRustHost") {
                    try {
                        if (!bridgeHostRegistered) {
                            System.loadLibrary("omnix_nexus_bridge")
                            check(xyz.omniecosystem.omnix.nexus.MatterHostRegistration.register(
                                RegisteredMatterHost(applicationContext)
                            )) { "Matter host registration failed" }
                            bridgeHostRegistered = true
                        }
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error("MATTER_REGISTRATION", error.toString(), null)
                    }
                    return@setMethodCallHandler
                }
                val requestGeneration = generation
                if (call.method !in setOf("qualifyLifecycle", "qualifyControl", "qualifyDiscovery", "qualifyRustControl")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                  MatterProcessHost.submit(applicationContext, { error ->
                      runOnUiThread { if (!detached && generation == requestGeneration) result.error("MATTER_QUALIFICATION", error.toString(), null) }
                  }) { qualification ->
                    if (detached || generation != requestGeneration) return@submit
                    try {
                        val answer = if (call.method == "qualifyRustControl") {
                            qualification.rustControl()
                        } else if (call.method == "qualifyDiscovery") {
                            probeMatterDiscovery(applicationContext, qualification.operationalServiceName())
                        } else if (call.method == "qualifyControl") {
                            qualification.control(
                                call.argument<String>("address") ?: error("Missing light address"),
                                call.argument<Boolean>("commission") ?: false
                            )
                        } else {
                            qualification.startup()
                        }
                        runOnUiThread { if (!detached && generation == requestGeneration) result.success(answer) }
                    } catch (error: Throwable) {
                        runOnUiThread { if (!detached && generation == requestGeneration) result.error("MATTER_QUALIFICATION", error.toString(), null) }
                    }
                  }
                } catch (error: RejectedExecutionException) {
                    result.error("MATTER_BUSY", "Matter operation queue is full", null)
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        detached = true
        generation++
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // The SDK owns process-global native state. close() only releases GATT;
        // it is not safe to claim native teardown or force private finalization.
        detached = true
        generation++
        super.onDestroy()
    }
}
