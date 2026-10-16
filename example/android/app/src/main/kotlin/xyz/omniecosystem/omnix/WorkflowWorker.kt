// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.work.*
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// Consumer adapter only: Android wakes Dart; the existing Rust runner executes
// the persisted job. No model, plan generation or second step loop lives here.
// WorkManager supplies a best-effort wakeup, not an exact alarm or a continuously
// running agent. Missing completion evidence is a failure, never a blind retry.
class WorkflowWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    override fun doWork(): Result {
        val jobId = inputData.getString("jobId") ?: return Result.failure()
        val taskId = inputData.getString("taskId") ?: return Result.failure()
        val done = CountDownLatch(1)
        var succeeded = false
        main.post {
            if (isStopped) { done.countDown(); return@post }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val host = FlutterEngine(applicationContext)
                engine = host
                channel = MethodChannel(host.dartExecutor.binaryMessenger,
                    "xyz.omniecosystem.omnix/workflow_background")
                channel!!.setMethodCallHandler { call, reply ->
                    when (call.method) {
                        "input" -> reply.success(mapOf("jobId" to jobId, "taskId" to taskId))
                        "batteryStatus" -> {
                            val battery = applicationContext.registerReceiver(null,
                                IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                            val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                            val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                            if (scale <= 0 || level !in 0..scale) {
                                reply.success(mapOf("status" to "unavailable"))
                            } else {
                                val percent = level.toLong() * 100 / scale
                                reply.success(mapOf("status" to "succeeded", "percent" to percent,
                                    "report" to "Battery: $percent%."))
                            }
                        }
                        "notifyText" -> reply.success(WorkflowNotifications.post(applicationContext,
                            jobId.hashCode(), call.argument<String>("text"), jobId))
                        "complete" -> {
                            succeeded = call.argument<Boolean>("succeeded") == true
                            reply.success(null)
                            done.countDown()
                        }
                        else -> reply.notImplemented()
                    }
                }
                host.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "workflowBackgroundMain"))
            } catch (_: Exception) { done.countDown() }
        }
        val finished = done.await(120, TimeUnit.SECONDS)
        main.post { dispose() }
        // No blind retry: a lost acknowledgment can follow a real effect.
        return if (finished && succeeded && !isStopped) Result.success() else Result.failure()
    }

    override fun onStopped() { main.post { dispose() } }
    private fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        engine?.destroy()
        engine = null
    }
}

object WorkflowNotifications {
    fun allowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) &&
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    fun post(context: Context, id: Int, text: String?, tag: String = "foreground"): Map<String, Any> {
        if (text == null || text.isBlank() || text.length > 4000)
            return mapOf("status" to "invalid_arguments", "executionStarted" to false)
        if (!allowed(context)) return mapOf("status" to "denied", "reason" to "Notifications disabled.")
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("workflow", "Workflow reports",
            NotificationManager.IMPORTANCE_DEFAULT))
        if (manager.getNotificationChannel("workflow").importance == NotificationManager.IMPORTANCE_NONE)
            return mapOf("status" to "denied", "reason" to "Workflow notification channel disabled.")
        try {
            manager.notify(tag, id, NotificationCompat.Builder(context, "workflow")
                .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Omnix workflow")
                .setContentText(text).setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true).build())
        } catch (_: SecurityException) {
            return mapOf("status" to "denied", "reason" to "Notification permission revoked.")
        }
        return mapOf("status" to "succeeded", "posted" to true)
    }
}
