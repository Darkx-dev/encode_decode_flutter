package com.example.my_android_plugin

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.apk.axml.aXMLDecoder
import com.apk.axml.aXMLEncoder
import org.xmlpull.v1.XmlPullParserException
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class MainActivity : FlutterActivity() {

    private val CHANNEL = "my_android_plugin/decode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "decodeBinaryAXML" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGUMENT", "Missing 'path' argument", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val file = File(path)
                            val decodedXml = if (isBinaryXML(file)) {
                                FileInputStream(file).use { fis ->
                                    aXMLDecoder().decode(fis)
                                }
                            } else {
                                file.readText(Charsets.UTF_8)
                            }
                            result.success(decodedXml)
                        } catch (e: Exception) {
                            result.error("DECODE_ERROR", "Failed to decode: ${e.message}", e.stackTraceToString())
                        }
                    }

                     "encodeXml" -> {
                        val xmlContent = call.argument<String>("xmlContent")
                        if (xmlContent == null) {
                            result.error("INVALID_ARGUMENT", "Missing 'xmlContent' argument", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val encoder = aXMLEncoder()

                            val encodedBytes: ByteArray = encoder.encodeString(this, xmlContent)

                            result.success(encodedBytes)

                        } catch (e: XmlPullParserException) {
                            Log.e("AXMLDecoder", "XML Parsing Error during encode", e)
                            result.error("ENCODE_ERROR", "Invalid XML format: ${e.message}", null)
                        } catch (e: Exception) {
                            Log.e("AXMLDecoder", "Generic Error during encode", e)
                            result.error("ENCODE_ERROR", "An unexpected error occurred: ${e.message}", null)
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    // Updated to take a File object for convenience
    private fun isBinaryXML(file: File): Boolean {
        if (!file.exists() || !file.isFile) return false

        // AXML magic number: 0x00080003
        val magic = byteArrayOf(0x03, 0x00, 0x08, 0x00)
        
        return try {
            FileInputStream(file).use {
                val buffer = ByteArray(4)
                it.read(buffer)
                buffer.contentEquals(magic)
            }
        } catch (e: IOException) {
            false
        }
    }
}