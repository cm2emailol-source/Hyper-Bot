package com.hyperbot.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface

/**
 * Shadow clone: LISTENS ONLY on the local Wi-Fi for Hyper-Bot PC's key states (UDP port 47474).
 * - Never sends anything, never connects anywhere.
 * - Drops every packet that doesn't come from a private home-network address (192.168.x, 10.x, 172.16-31.x)
 *   or doesn't carry your pairing code.
 * Packet: "HB1|<code>|<seq>|<keys>"  keys = w a s d space left right (1/0 each, e.g. "1000100")
 */
class CloneLink(private val ctx: Context, private val code: String, private val onKeys: (String) -> Unit) {
    @Volatile private var running = false
    private var socket: DatagramSocket? = null
    private var lock: WifiManager.MulticastLock? = null
    private val main = Handler(Looper.getMainLooper())
    @Volatile var packets = 0
        private set

    fun start() {
        if (running) return
        running = true
        try {
            val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            lock = wm.createMulticastLock("hyperbot-clone").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) {}
        Thread {
            try {
                val s = DatagramSocket(null).apply {
                    reuseAddress = true
                    broadcast = true
                    soTimeout = 1000
                    bind(InetSocketAddress(PORT))
                }
                socket = s
                val buf = ByteArray(256)
                var lastSeq = -1L
                while (running) {
                    val p = DatagramPacket(buf, buf.size)
                    try { s.receive(p) } catch (_: java.net.SocketTimeoutException) { continue }
                    if (!p.address.isSiteLocalAddress) continue                 // home network only
                    val parts = String(p.data, 0, p.length, Charsets.UTF_8).trim().split("|")
                    if (parts.size < 4 || parts[0] != "HB1" || parts[1] != code) continue
                    val seq = parts[2].toLongOrNull() ?: continue
                    if (seq <= lastSeq && lastSeq - seq < 1000) continue        // old / duplicate packet
                    lastSeq = seq
                    packets++
                    val keys = parts[3]
                    main.post { onKeys(keys) }
                }
            } catch (_: Exception) {
            } finally {
                socket?.close()
            }
        }.apply { isDaemon = true }.start()
    }

    fun stop() {
        running = false
        socket?.close()
        try { lock?.release() } catch (_: Exception) {}
    }

    companion object {
        const val PORT = 47474

        /** This tablet's Wi-Fi address, to type into Hyper-Bot PC. */
        fun localIp(): String = try {
            NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }
                .firstOrNull { it is Inet4Address && it.isSiteLocalAddress }?.hostAddress ?: "unknown"
        } catch (_: Exception) { "unknown" }
    }
}
