package com.shike.local.shike

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32
import javax.net.ssl.*
import javax.security.auth.x500.X500Principal

/** One-use LAN TLS transfer. Trust is pinned to the certificate carried by QR. */
class ShikeNearbyTransfer(private val context: Context, private val received: (String) -> Unit) {
    companion object { const val MAX_BYTES = 512L * 1024 * 1024 }
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val random = SecureRandom()
    private val lock = Any()
    @Volatile private var generation = 0
    private var listener: SSLServerSocket? = null
    private var connection: SSLSocket? = null
    private var alias: String? = null

    private fun encode(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)
    private fun wifiAddress(): InetAddress {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (network in manager.allNetworks) {
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            val address = manager.getLinkProperties(network)?.linkAddresses?.map { it.address }
                ?.firstOrNull { it is Inet4Address && it.isSiteLocalAddress }
            if (address != null) return address
        }
        throw IllegalStateException("请让两部手机连接同一个 Wi-Fi")
    }
    fun start(): String {
        stop()
        val address = wifiAddress()
        val session = UUID.randomUUID().toString()
        val certificateAlias = "shike-nearby-$session"
        val token = ByteArray(32).also(random::nextBytes)
        val end = Instant.now().plusSeconds(600)
        val gen: Int
        val server: SSLServerSocket
        val cert: ByteArray
        synchronized(lock) {
            generation++; gen = generation
            alias = certificateAlias
            try {
                val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                generator.initialize(KeyGenParameterSpec.Builder(certificateAlias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                    .setCertificateSubject(X500Principal("CN=Shike Nearby"))
                    .setCertificateNotBefore(Date(System.currentTimeMillis() - 86400000))
                    .setCertificateNotAfter(Date(System.currentTimeMillis() + 86400000))
                    .build())
                generator.generateKeyPair()
                val androidKeys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                cert = androidKeys.getCertificate(certificateAlias).encoded
                val managers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(androidKeys, null) }
                // Select just this ephemeral key, rather than any older app certificate.
                val base = managers.keyManagers.filterIsInstance<X509KeyManager>().first()
                val keyManager = object : X509KeyManager by base {
                    override fun chooseServerAlias(keyType: String?, issuers: Array<java.security.Principal>?, socket: java.net.Socket?) = if (keyType == "EC") certificateAlias else null
                }
                val tls = SSLContext.getInstance("TLS").apply { init(arrayOf(keyManager), null, random) }
                server = tls.serverSocketFactory.createServerSocket() as SSLServerSocket
                server.enabledProtocols = arrayOf("TLSv1.2")
                server.reuseAddress = true
                server.bind(InetSocketAddress(address,0))
                listener = server
            } catch (e: Exception) { stop(); throw e }
        }
        timer.schedule({ if (generation == gen) stop() },600,TimeUnit.SECONDS)
        Thread({ receiveLoop(server,token,end,gen) },"shike-nearby-receive").start()
        return JSONObject().put("version",2).put("session",session).put("host",address.hostAddress).put("port",server.localPort)
            .put("key",encode(token)).put("certificate",encode(cert)).put("expires",end.toString()).toString()
    }

    private fun receiveLoop(server: SSLServerSocket, token: ByteArray, end: Instant, gen: Int) {
        var staged: File? = null
        try {
            while (generation == gen && Instant.now().isBefore(end)) {
                val client = server.accept() as SSLSocket
                synchronized(lock) { if (generation != gen) { client.close(); return }; connection = client }
                try {
                    client.soTimeout = 30000
                    client.startHandshake()
                    val input = DataInputStream(client.inputStream)
                    val supplied = ByteArray(32); input.readFully(supplied)
                    if (!MessageDigest.isEqual(token,supplied)) throw IllegalArgumentException("配对不匹配")
                    val header = ByteArray(4); input.readFully(header)
                    require(header.contentEquals("SHK2".toByteArray(Charsets.US_ASCII))) { "传输协议不符" }
                    val length = input.readLong()
                    require(length in 1..MAX_BYTES) { "传输包过大或为空" }
                    val expected = input.readInt().toLong() and 0xFFFFFFFFL
                    val directory = File(context.dataDir,"app_flutter/complete-imports/staging/nearby").apply { mkdirs() }
                    staged = File.createTempFile("transfer-",".zip",directory)
                    val crc = CRC32()
                    staged.outputStream().buffered().use { out ->
                        val buffer = ByteArray(65536)
                        var remaining = length
                        while (remaining > 0) {
                            if (generation != gen) throw IllegalStateException("传输已取消")
                            val n = input.read(buffer,0,minOf(buffer.size.toLong(),remaining).toInt())
                            require(n > 0) { "传输中断，请重新发送" }
                            crc.update(buffer,0,n); out.write(buffer,0,n); remaining -= n
                        }
                    }
                    require(crc.value == expected) { "传输内容损坏" }
                    client.outputStream.write(1); client.outputStream.flush()
                    val file = staged; staged = null
                    synchronized(lock) {
                        if (generation == gen) { received(file!!.absolutePath); stop() } else file?.delete()
                    }
                    return
                } catch (_: Exception) {
                    staged?.delete(); staged = null
                    client.close()
                    // A foreign or interrupted connection does not consume the pairing.
                    synchronized(lock) { if (connection === client) connection = null }
                }
            }
        } catch (_: Exception) {
            staged?.delete()
        } finally { if (generation == gen) stop() }
    }

    fun send(pairing: String, bytes: ByteArray) {
        val j = JSONObject(pairing)
        require(j.optInt("version") == 2) { "请使用安卓配对码；iPhone 请通过备份文件导入" }
        val end = Instant.parse(j.getString("expires"))
        require(end.isAfter(Instant.now()) && end.isBefore(Instant.now().plusSeconds(601))) { "配对码已过期" }
        val host = j.getString("host")
        require(host.matches(Regex("[0-9.]+"))) { "配对地址无效" }
        val address = InetAddress.getByName(host)
        require(address is Inet4Address && address.isSiteLocalAddress && !address.isLoopbackAddress) { "配对地址无效" }
        val port = j.getInt("port"); require(port in 1..65535)
        val token = decode(j.getString("key")); require(token.size == 32)
        val pin = decode(j.getString("certificate")); require(pin.size in 100..8192)
        require(bytes.size.toLong() in 17..MAX_BYTES + 16)
        wifiAddress()
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers() = emptyArray<X509Certificate>()
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) { throw java.security.cert.CertificateException("不接受客户端证书") }
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                if (chain.size != 1 || !MessageDigest.isEqual(chain[0].encoded,pin)) throw java.security.cert.CertificateException("配对设备不匹配")
            }
        }
        val tls = SSLContext.getInstance("TLS").apply { init(null,arrayOf(trust),random) }
        val socket = tls.socketFactory.createSocket() as SSLSocket
        synchronized(lock) { check(connection == null) { "正在传输" }; connection = socket }
        try {
            socket.enabledProtocols = arrayOf("TLSv1.2"); socket.soTimeout = 30000
            socket.connect(InetSocketAddress(address,port),10000); socket.startHandshake()
            val out = DataOutputStream(socket.outputStream)
            out.write(token)
            var offset = 0
            while (offset < bytes.size) { val n = minOf(65536,bytes.size-offset); out.write(bytes,offset,n); offset += n }
            out.flush()
            check(socket.inputStream.read() == 1) { "对方未完整收到，请重新发送" }
        } finally { socket.close(); synchronized(lock) { if (connection === socket) connection = null } }
    }

    fun stop() = synchronized(lock) {
        generation++
        try { listener?.close() } catch (_: Exception) {}
        try { connection?.close() } catch (_: Exception) {}
        listener = null; connection = null
        alias?.let { try { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(it) } catch (_: Exception) {} }
        alias = null
    }
    fun close() { stop(); timer.shutdownNow() }
}
