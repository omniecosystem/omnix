// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.wifi.WifiManager
import android.content.Context

class MainActivity : FlutterActivity() {
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        agentHost?.onPermissionsResult(requestCode)
    }
    private var agentHost: AgentHost? = null
    companion object { private var matterHostRegistered = false }
    private var matterLock: WifiManager.MulticastLock? = null
    private var hostChannel: MethodChannel? = null
    private var networkChannel: MethodChannel? = null
    @Volatile private var hostGeneration = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        detachHosts()
        super.configureFlutterEngine(flutterEngine)
        agentHost = AgentHost(this, flutterEngine.dartExecutor.binaryMessenger)
        hostGeneration++
        hostChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "xyz.omniecosystem.omnix/matter_host")
        hostChannel!!.setMethodCallHandler { call, result ->
            val requestGeneration = hostGeneration
            if (call.method == "register") {
                try {
                    if (!matterHostRegistered) {
                        System.loadLibrary("omnix_nexus_bridge")
                        check(xyz.omniecosystem.omnix.nexus.MatterHostRegistration.register(
                            xyz.omniecosystem.qualification.omnix_matter_android_app.RegisteredMatterHost(applicationContext)
                        )) { "Matter registration failed" }
                        matterHostRegistered = true
                    }
                    result.success(null)
                } catch (error: Throwable) { result.error("MATTER_HOST", error.toString(), null) }
            } else if (call.method == "commissionFixture") {
                val address = call.argument<String>("address") ?: ""
                try {
                    xyz.omniecosystem.qualification.omnix_matter_android_app.MatterProcessHost.submit(applicationContext,
                        { error -> runOnUiThread { if (requestGeneration == hostGeneration) result.error("MATTER_FIXTURE", error.toString(), null) } }
                    ) { owner ->
                        val answer = owner.control(address, true)
                        runOnUiThread { if (requestGeneration == hostGeneration) result.success(answer) }
                    }
                } catch (error: Throwable) { result.error("MATTER_FIXTURE", error.toString(), null) }
            } else { result.notImplemented() }
        }
        networkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "xyz.omniecosystem.omnix/matter_network")
        networkChannel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "acquire" -> {
                        if (matterLock?.isHeld != true) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            matterLock = wifi.createMulticastLock("omnix-matter-experiment").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    }
                    "release" -> { releaseMatterLock(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("matter_network", error.message, null)
            }
        }
    }

    private fun releaseMatterLock() {
        matterLock?.let { if (it.isHeld) it.release() }
        matterLock = null
    }

    private fun detachHosts() {
        agentHost?.close()
        agentHost = null
        hostGeneration++
        hostChannel?.setMethodCallHandler(null)
        hostChannel = null
        networkChannel?.setMethodCallHandler(null)
        networkChannel = null
        releaseMatterLock()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        detachHosts()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        detachHosts()
        super.onDestroy()
    }
}
