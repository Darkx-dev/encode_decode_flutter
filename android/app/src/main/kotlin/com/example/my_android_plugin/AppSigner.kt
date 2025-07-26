package com.example.my_android_plugin

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
            .setV1SigningEnabled(true)
            .setV2SigningEnabled(true)

        // V3 is supported from API 28 (Pie) onwards.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setV3SigningEnabled(true)
        }
        // I don't like things getting complicated so PHACK V4 Signing
        builder.setV4SigningEnabled(false)

        // This will now only perform V1/V2/V3 signing and will not throw the error.
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
        val beginMarker = "-----BEGIN CERTIFICATE-----"
        val endMarker = "-----END CERTIFICATE-----"
        val beginIndex = pemFileContent.indexOf(beginMarker)
        val endIndex = pemFileContent.indexOf(endMarker)

        if (beginIndex == -1 || endIndex == -1) {
            throw CertificateException("Could not find certificate markers in cert.pem.")
        }

        val certificatePem = pemFileContent.substring(beginIndex, endIndex + endMarker.length)
        val certificate = certificatePem.byteInputStream(Charsets.UTF_8).use {
            CertificateFactory.getInstance("X.509").generateCertificate(it) as X509Certificate
        }
        
        return Pair(privateKey, certificate)
    }
}