package com.example.my_android_plugin

import android.content.Context
import android.os.Build
import com.android.apksig.ApkSigner
import java.io.File
import java.io.InputStream
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Collections

class AppSigner(private val context: Context) {

    // These filenames match what you'll copy from assets
    private val privateKeyFile = File(context.filesDir, "testkey.pk8")
    private val certificateFile = File(context.filesDir, "testkey.x509.pem")

    /**
     * Signs the input APK file and saves it to the output file.
     */
    fun sign(inputFile: File, outputFile: File) {
        val (privateKey, certificate) = loadSigningKeys()

        val signerConfig = ApkSigner.SignerConfig.Builder("CERT", privateKey, listOf(certificate)).build()
        val builder = ApkSigner.Builder(listOf(signerConfig))
            .setInputApk(inputFile)
            .setOutputApk(outputFile)
            .setCreatedBy("My Flutter App")
            .setV1SigningEnabled(true)
            .setV2SigningEnabled(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setV3SigningEnabled(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setV4SigningEnabled(true)
        }

        builder.build().sign()
    }

    /**
     * Loads the private key and certificate from the app's private files directory.
     */
    private fun loadSigningKeys(): Pair<PrivateKey, X509Certificate> {
        // Load the private key bytes
        val keyBytes = privateKeyFile.readBytes()
        val keySpec = PKCS8EncodedKeySpec(keyBytes)
        // This is the standard way to load a PKCS#8 private key
        val privateKey = KeyFactory.getInstance("RSA").generatePrivate(keySpec)

        // Load the certificate
        val certificate = certificateFile.inputStream().use {
            CertificateFactory.getInstance("X.509").generateCertificate(it) as X509Certificate
        }

        return Pair(privateKey, certificate)
    }
}