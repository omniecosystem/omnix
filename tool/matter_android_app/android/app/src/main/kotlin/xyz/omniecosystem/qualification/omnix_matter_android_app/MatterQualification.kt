package xyz.omniecosystem.qualification.omnix_matter_android_app

import android.content.Context
import chip.devicecontroller.*
import java.security.MessageDigest
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

// Qualification only: explicit test PAA, one retained native controller per process.
class MatterQualification(context: Context) {
    private val ownerId = java.util.UUID.randomUUID().toString()
    private val controller = ChipDeviceController(
        ControllerParams.newBuilder().setControllerVendorId(0xFFF4)
            .setUdpListenPort(0).setSkipAttestationCertificateValidation(false).build()
    )
    private val nodeId = 0x12344321L
    private val paa = context.assets.open("Chip-Test-PAA-NoVID-Cert.der").use { it.readBytes() }
    private var trustLookups = 0
    private var hostBlocked = false

    init {
        val hash = MessageDigest.getInstance("SHA-256").digest(paa)
            .joinToString("") { "%02x".format(it) }
        check(hash == "178632f8f235c0fa6a820de1d4c9b69568e2d16b7c2912b22f056136df75babc")
        controller.setAttestationTrustStoreDelegate(object : AttestationTrustStoreDelegate {
            override fun getProductAttestationAuthorityCert(skid: ByteArray): ByteArray? {
                synchronized(this@MatterQualification) { trustLookups++ }
                return if (DeviceAttestation.extractSkidFromPaaCert(paa).contentEquals(skid)) paa else null
            }
        })
    }

    fun startup(): Map<String, Any> {
        check(controller.deviceControllerPtr != 0L)
        return mapOf("jniLoaded" to true, "ownerId" to ownerId, "fabricIndex" to controller.fabricIndex,
            "nodeId" to controller.controllerNodeId.toString(), "testTrustConfigured" to true)
    }

    fun operationalServiceName(): String =
        java.lang.Long.toUnsignedString(controller.compressedFabricId, 16)
            .uppercase().padStart(16, '0') + "-" +
        java.lang.Long.toUnsignedString(nodeId, 16).uppercase().padStart(16, '0')

    private fun <T> hostDevice(node: String, endpoint: Int, operation: (ChipClusters.OnOffCluster) -> T): T {
        require(node == nodeId.toString() && endpoint == 1) { "Unknown qualification device" }
        check(!hostBlocked) { "Rust host requires process restart after a native failure" }
        try {
        val connected = CompletableFuture<Long>()
        controller.getConnectedDevicePointer(nodeId,
            object : GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback {
                override fun onDeviceConnected(pointer: Long) { connected.complete(pointer) }
                override fun onConnectionFailure(id: Long, error: Exception) { connected.completeExceptionally(error) }
            })
        val pointer = connected.get(60, TimeUnit.SECONDS)
        check(pointer != 0L)
        // On failure/timeout preserve callback ownership until process exit.
        val answer = operation(ChipClusters.OnOffCluster(pointer, endpoint))
        controller.releaseConnectedDevicePointer(pointer)
        return answer
        } catch (error: Throwable) {
            hostBlocked = true
            throw error
        }
    }

    // Block body guarantees JVM void (V), matching the JNI command contract.
    fun hostSetOnOff(node: String, endpoint: Int, on: Boolean) {
      hostDevice(node, endpoint) { cluster ->
        val finished = CompletableFuture<Unit>()
        val callback = object : ChipClusters.DefaultClusterCallback {
            override fun onSuccess() { finished.complete(Unit) }
            override fun onError(error: Exception) { finished.completeExceptionally(error) }
        }
        if (on) cluster.on(callback) else cluster.off(callback)
        finished.get(30, TimeUnit.SECONDS)
      }
    }

    fun hostReadOnOff(node: String, endpoint: Int): Boolean = hostDevice(node, endpoint) { cluster ->
        val read = CompletableFuture<Boolean>()
        cluster.readOnOffAttribute(object : ChipClusters.BooleanAttributeCallback {
            override fun onSuccess(value: Boolean) { read.complete(value) }
            override fun onError(error: Exception) { read.completeExceptionally(error) }
        })
        read.get(30, TimeUnit.SECONDS)
    }

    fun rustControl(): Map<String, Any> {
        check(RustMatterHost.verify(this)) { "Rust host command/readback verification failed" }
        return startup() + mapOf("rustOnOffVerified" to true, "nativeOwnerRetained" to true,
            "trustLookups" to synchronized(this) { trustLookups })
    }

    fun control(address: String, commission: Boolean): Map<String, Any> {
        require(address.matches(Regex("[0-9a-fA-F:.%]+"))) { "Use a literal LAN IP address" }
        if (commission) {
            val paired = CompletableFuture<Unit>()
            controller.setCompletionListener(object : ChipDeviceController.CompletionListener {
                override fun onCommissioningComplete(id: Long, code: Long) {
                    if (id != nodeId || code != 0L) paired.completeExceptionally(
                        IllegalStateException("Commissioning failed: $id / $code"))
                    else paired.complete(Unit)
                }
                override fun onPairingComplete(code: Long) {
                    if (code != 0L) paired.completeExceptionally(IllegalStateException("Pairing failed: $code"))
                }
                override fun onError(error: Throwable) { paired.completeExceptionally(error) }
                override fun onCommissioningStatusUpdate(id: Long, stage: String, code: Long) {}
                override fun onCommissioningStageStart(id: Long, stage: String) {}
                override fun onConnectDeviceComplete() {}
                override fun onStatusUpdate(status: Int) {}
                override fun onPairingDeleted(code: Long) {}
                override fun onReadCommissioningInfo(a: Int, b: Int, c: Int, d: Int) {}
                override fun onNotifyChipConnectionClosed() {}
                override fun onCloseBleComplete() {}
                override fun onOpCSRGenerationComplete(csr: ByteArray) {}
                override fun onICDRegistrationInfoRequired() {}
                override fun onICDRegistrationComplete(code: Long, info: ICDDeviceInfo) {}
            })
            controller.pairDeviceWithAddress(nodeId, address, 5542, 3840, 20202021L, null as ByteArray?)
            try { paired.get(120, TimeUnit.SECONDS) } catch (error: Exception) {
                controller.stopDevicePairing(nodeId)
                throw error
            }
            check(synchronized(this) { trustLookups > 0 }) { "Test PAA was never consulted" }
        }
        val connected = CompletableFuture<Long>()
        controller.getConnectedDevicePointer(nodeId,
            object : GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback {
                override fun onDeviceConnected(pointer: Long) { connected.complete(pointer) }
                override fun onConnectionFailure(id: Long, error: Exception) {
                    connected.completeExceptionally(error)
                }
            })
        val pointer = connected.get(60, TimeUnit.SECONDS)
        check(pointer != 0L)
        val cluster = ChipClusters.OnOffCluster(pointer, 1)
        // Release only after all callbacks complete. On timeout, retain the native
        // owner until process exit instead of freeing a pointer still in use.
        for (on in listOf(true, false)) {
            val command = CompletableFuture<Unit>()
            val callback = object : ChipClusters.DefaultClusterCallback {
                override fun onSuccess() { command.complete(Unit) }
                override fun onError(error: Exception) { command.completeExceptionally(error) }
            }
            if (on) cluster.on(callback) else cluster.off(callback)
            command.get(30, TimeUnit.SECONDS)
            val read = CompletableFuture<Boolean>()
            cluster.readOnOffAttribute(object : ChipClusters.BooleanAttributeCallback {
                override fun onSuccess(value: Boolean) { read.complete(value) }
                override fun onError(error: Exception) { read.completeExceptionally(error) }
            })
            check(read.get(30, TimeUnit.SECONDS) == on) { "OnOff readback mismatch" }
        }
        controller.releaseConnectedDevicePointer(pointer)
        return startup() + mapOf("commissionedNow" to commission, "onOffVerified" to true,
            "trustLookups" to synchronized(this) { trustLookups })
    }
}
