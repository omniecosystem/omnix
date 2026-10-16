// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
package xyz.omniecosystem.omnix

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.CalendarContract
import android.content.ActivityNotFoundException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import androidx.work.*
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors

// Host-owned Android capabilities. The Rust agent loop supplies authorized calls;
// Android permissions and host-side argument validation still apply here.
class AgentHost(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "xyz.omniecosystem.omnix/agent_host")
    private val handler = Handler(Looper.getMainLooper())
    private var dialog: AlertDialog? = null
    private var pending: MethodChannel.Result? = null
    private var expiry: Runnable? = null
    private var notificationPermission: PendingPermissionAction? = null
    private var notificationExpiry: Runnable? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryStatus" -> readBattery(result)
                "shareText" -> requestShare(call.arguments, result)
                "deviceInfo" -> result.success(mapOf(
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "androidApi" to Build.VERSION.SDK_INT
                ))
                "openSettings" -> requestSettings(call.arguments, result)
                "prepareCalendarEvent" -> requestCalendar(call.arguments, result)
                "scheduleWorkflow" -> scheduleWorkflow(call.arguments, result)
                "notifyText" -> result.success(WorkflowNotifications.post(activity,
                    (call.argument<String>("receiptId") ?: "foreground").hashCode(), call.argument<String>("text")))
                "cancelPending" -> { cancelPending(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleWorkflow(raw: Any?, result: MethodChannel.Result) {
        val args = raw as? Map<*, *>
        val jobId = args?.get("jobId") as? String
        val taskId = args?.get("taskId") as? String
        val delay = (args?.get("delaySeconds") as? Number)?.toLong()
        if (jobId == null || taskId == null || jobId.length !in 1..256 || taskId.length !in 1..256 ||
            delay == null || delay !in 10..86400) {
            result.success(mapOf("status" to "invalid_arguments")); return
        }
        val enqueue = {
            if (!WorkflowNotifications.allowed(activity)) {
                result.success(mapOf("status" to "denied", "reason" to "Enable notifications before scheduling."))
            } else {
                val work = OneTimeWorkRequestBuilder<WorkflowWorker>()
                    .setInitialDelay(delay, TimeUnit.SECONDS)
                    .setInputData(workDataOf("jobId" to jobId, "taskId" to taskId)).build()
                val operation = WorkManager.getInstance(activity.applicationContext)
                    .enqueueUniqueWork("omnix-workflow-$jobId", ExistingWorkPolicy.KEEP, work)
                val executor = Executors.newSingleThreadExecutor()
                executor.execute {
                    val receipt = try {
                        operation.result.get()
                        mapOf("status" to "scheduled", "jobId" to jobId, "notBeforeSeconds" to delay,
                            "exactTiming" to false)
                    } catch (_: Exception) { mapOf("status" to "unavailable") }
                    handler.post { result.success(receipt) }
                    executor.shutdown()
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            if (notificationPermission != null) {
                result.success(mapOf("status" to "blocked")); return
            }
            val permission = PendingPermissionAction.create(enqueue) {
                result.success(mapOf("status" to "denied", "reason" to "Permission request cancelled, expired or host closed."))
            }
            if (permission == null) {
                result.success(mapOf("status" to "unavailable", "reason" to "Permission request identifiers exhausted.")); return
            }
            notificationPermission = permission
            notificationExpiry = Runnable {
                if (notificationPermission === permission) cancelNotificationPermission()
            }
            handler.postDelayed(notificationExpiry!!, 20_000)
            try {
                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permission.requestCode)
            } catch (_: Exception) { cancelNotificationPermission() }
        } else { enqueue() }
    }

    fun onPermissionsResult(requestCode: Int) {
        val permission = notificationPermission ?: return
        if (requestCode != permission.requestCode) return
        notificationPermission = null
        clearNotificationExpiry()
        permission.complete(requestCode)
    }

    private fun clearNotificationExpiry() {
        notificationExpiry?.let { handler.removeCallbacks(it) }
        notificationExpiry = null
    }

    private fun cancelNotificationPermission() {
        val permission = notificationPermission
        notificationPermission = null
        clearNotificationExpiry()
        permission?.cancel()
    }

    private fun cancelPending() {
        cancelNotificationPermission()
        finish("denied")
    }

    private fun readBattery(result: MethodChannel.Result) {
        try {
            val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val state = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            if (scale <= 0 || level < 0 || level > scale || state !in 1..5) {
                result.success(mapOf("status" to "unavailable", "reason" to "Battery status unavailable."))
                return
            }
            val percent = (level.toLong() * 100 / scale).toInt()
            val charging = state == BatteryManager.BATTERY_STATUS_CHARGING || state == BatteryManager.BATTERY_STATUS_FULL
            val chargingText = if (state == BatteryManager.BATTERY_STATUS_UNKNOWN) "charging state unknown"
                else if (charging) "charging" else "not charging"
            result.success(mapOf("status" to "succeeded", "percent" to percent,
                "charging" to if (state == BatteryManager.BATTERY_STATUS_UNKNOWN) null else charging,
                "report" to "Battery: $percent%, $chargingText."))
        } catch (_: Exception) {
            result.success(mapOf("status" to "unavailable", "reason" to "Battery status unavailable."))
        }
    }

    private fun requestShare(raw: Any?, result: MethodChannel.Result) {
        val args = raw as? Map<*, *>
        val text = args?.get("text") as? String
        val authorized = args?.get("engineAuthorized") == true
        val expected = setOf("text") + if (authorized) setOf("engineAuthorized") else emptySet()
        if (args?.keys != expected || text == null || text.isBlank() || text.length > 4000) {
            result.success(mapOf("status" to "invalid_arguments", "executionStarted" to false))
            return
        }
        val share = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        requestApproval(result, "Share text?", "Opens a chooser only. You choose where and whether to send.\n\n$text",
            "Open share sheet", Intent.createChooser(share, "Share report"), "editor_opened", !authorized)
    }

    private fun requestSettings(raw: Any?, result: MethodChannel.Result) {
        val authorized = (raw as? Map<*, *>)?.get("engineAuthorized") == true
        requestApproval(result, "Allow Omnix to open Settings?",
            "This opens Android Settings only. It does not change any settings.",
            "Open Settings", Intent(Settings.ACTION_SETTINGS), "opened", !authorized)
    }

    private fun requestCalendar(raw: Any?, result: MethodChannel.Result) {
        val args = raw as? Map<*, *>
        val title = args?.get("title") as? String
        val location = args?.get("location") as? String
        val description = args?.get("description") as? String
        val start = args?.get("startMillis") as? Long
        val end = args?.get("endMillis") as? Long
        // Independently validate at the platform boundary, even if Dart validated.
        val authorized = args?.get("engineAuthorized") == true
        val expectedKeys = setOf("title", "location", "description", "startMillis", "endMillis") +
            if (authorized) setOf("engineAuthorized") else emptySet()
        if (args?.keys != expectedKeys || title == null || title.isBlank() || title.length > 200 ||
            location == null || location.length > 500 ||
            description == null || description.length > 2000 ||
            start == null || end == null || start < 946684800000L ||
            end > 4133980800000L || end <= start || end - start > 604800000L) {
            result.success(mapOf("status" to "invalid_arguments"))
            return
        }
        val intent = Intent(Intent.ACTION_INSERT).setDataAndType(
            CalendarContract.Events.CONTENT_URI, "vnd.android.cursor.item/event")
            .putExtra(CalendarContract.Events.TITLE, title)
            .putExtra(CalendarContract.Events.EVENT_LOCATION, location)
            .putExtra(CalendarContract.Events.DESCRIPTION, description)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
        val startText = java.time.Instant.ofEpochMilli(start).toString()
        val endText = java.time.Instant.ofEpochMilli(end).toString()
        requestApproval(result, "Review calendar proposal",
            "$title\n$startText → $endText (UTC)\nLocation: $location\n$description\n\n" +
            "Opens the calendar editor only. Review and save there; no event is saved here.",
            "Open calendar editor", intent, "editor_opened", !authorized)
    }

    private fun requestApproval(result: MethodChannel.Result, title: String,
                                message: String, positive: String,
                                intent: Intent, openedStatus: String, reviewRequired: Boolean = true) {
        if (pending != null || activity.isFinishing || activity.isDestroyed) {
            result.success(mapOf("status" to "denied", "reason" to "Host unavailable or busy"))
            return
        }
        pending = result
        // Trusted consumer wiring only, never a model argument or OS permission bypass.
        if (!reviewRequired) {
            openIntent(intent, openedStatus)
            return
        }
        dialog = AlertDialog.Builder(activity)
            .setTitle(title)
            .setMessage(message)
            .setNegativeButton("Cancel") { _, _ -> finish("denied") }
            .setPositiveButton(positive) { _, _ ->
                if (pending != null && !activity.isFinishing && !activity.isDestroyed) {
                    openIntent(intent, openedStatus)
                } else { finish("denied") }
            }
            .setOnCancelListener { finish("denied") }
            .create()
        // Expire before the bridge's 30-second host wait. No indefinitely live approval.
        expiry = Runnable { finish("denied") }
        handler.postDelayed(expiry!!, 20_000)
        dialog!!.show()
    }

    private fun openIntent(intent: Intent, openedStatus: String) {
        try {
            activity.startActivity(intent)
            finish(openedStatus)
        } catch (_: ActivityNotFoundException) {
            finish("unavailable", "No installed app could handle this request.")
        } catch (_: Exception) {
            finish("failed", "The host could not open the requested screen.")
        }
    }

    private fun finish(status: String, reason: String? = null) {
        val result = pending ?: return
        pending = null
        expiry?.let { handler.removeCallbacks(it) }
        expiry = null
        dialog?.dismiss()
        dialog = null
        result.success(if (reason == null) mapOf("status" to status)
            else mapOf("status" to status, "reason" to reason))
    }

    fun close() {
        cancelPending()
        channel.setMethodCallHandler(null)
    }
}
