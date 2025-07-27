package com.example.my_android_plugin

import java.util.Base64
import android.content.Context
import android.os.Build
import com.android.apksig.ApkSigner
import java.io.File
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec

class AppSigner(private val context: Context) {

    private val privateKeyFile = File(context.filesDir, "app_key.pk8")
    private val certificateFile = File(context.filesDir, "app_cert.pem")

    /**
     * Signs the input APK file and saves it to the output file.
     */
    fun sign(inputFile: File, outputFile: File) {
        val (privateKey, certificate) = loadSigningKeys()

        val signerConfig = ApkSigner.SignerConfig.Builder("CERT", privateKey, listOf(certificate)).build()
        
        val builder = ApkSigner.Builder(listOf(signerConfig))
            .setInputApk(inputFile)
            .setOutputApk(outputFile)
            .setCreatedBy("My Flutter XML Editor")

        builder.setMinSdkVersion(-1)
        builder.setV1SigningEnabled(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setV2SigningEnabled(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setV3SigningEnabled(true)
        }
        
        builder.setV4SigningEnabled(false)

        builder.build().sign()
    }

    /**
     * Loads the private key and certificate from the app's private files directory.
     * This contains the fix for the PEM certificate parsing error.
     */
    private fun loadSigningKeys(): Pair<PrivateKey, X509Certificate> {
        val keyBytes = privateKeyFile.readBytes()
        val keySpec = PKCS8EncodedKeySpec(keyBytes)
        val privateKey = KeyFactory.getInstance("RSA").generatePrivate(keySpec)

        val pemFileContent = certificateFile.readText(Charsets.UTF_8)
        val base64Cert = pemFileContent
            .replace("-----BEGIN CERTIFICATE-----", "")
            .replace("-----END CERTIFICATE-----", "")
            .replace("\\s".toRegex(), "")

        if (base64Cert.isEmpty()) {
            throw SecurityException("Could not find Base64 content in cert.pem.")
        }

        val decodedCert = Base64.getDecoder().decode(base64Cert)
        val certificate = decodedCert.inputStream().use {
            CertificateFactory.getInstance("X.509").generateCertificate(it) as X509Certificate
        }

        return Pair(privateKey, certificate)
    }

}