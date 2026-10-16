package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.SystemClock
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

// Diagnostic only: Android NSD, independently of the SDK's five-second browse.
// No IP-address injection, credential modification, or replacement resolver.
fun probeMatterDiscovery(context: Context, target: String): Map<String, Any> {
    val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    val multicast = wifi.createMulticastLock("omnix-matter-discovery-probe")
    val found = ConcurrentHashMap.newKeySet<String>()
    val started = AtomicBoolean(false)
    val answer = CompletableFuture<Boolean>()
    val start = SystemClock.elapsedRealtime()
    val listener = object : NsdManager.DiscoveryListener {
        override fun onDiscoveryStarted(type: String) { started.set(true) }
        override fun onServiceFound(service: NsdServiceInfo) {
            found.add(service.serviceName)
            if (service.serviceName.equals(target, ignoreCase = true)) answer.complete(true)
        }
        override fun onServiceLost(service: NsdServiceInfo) {}
        override fun onDiscoveryStopped(type: String) { started.set(false) }
        override fun onStartDiscoveryFailed(type: String, code: Int) {
            answer.completeExceptionally(IllegalStateException("NSD start failed: $code"))
        }
        override fun onStopDiscoveryFailed(type: String, code: Int) {}
    }
    multicast.acquire()
    try {
        nsd.discoverServices("_matter._tcp.", NsdManager.PROTOCOL_DNS_SD, listener)
        val seen = try { answer.get(20, TimeUnit.SECONDS) }
            catch (_: TimeoutException) { false }
        return mapOf("targetSeen" to seen, "matterServiceCount" to found.size,
            "elapsedMs" to SystemClock.elapsedRealtime() - start, "target" to target)
    } finally {
        try {
            if (started.get()) nsd.stopServiceDiscovery(listener)
        } finally {
            if (multicast.isHeld) multicast.release()
        }
    }
}
