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
import java.io.FileOutputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "my_android_plugin/decode"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "decodeBinaryAXML" -> handleDecodeAXML(call, result)
                    "encodeXml" -> handleEncodeXML(call, result)
                    "buildAndSignApk" -> handleBuildAndSignApk(call, result)
                    "debugListAssets" -> handleDebugListAssets(call, result)
                    else -> result.notImplemented()
                }
            }
        }
        
        private fun handleDecodeAXML(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("INVALID_ARGUMENT", "Missing 'path' argument", null)
                return
            }

            try {
                val file = File(path)
                val decodedXml = if (isBinaryXML(file)) {
                    FileInputStream(file).use { fis -> aXMLDecoder().decode(fis) }
                } else {
                    file.readText(Charsets.UTF_8)
                }
                result.success(decodedXml)
            } catch (e: Exception) {
                result.error("DECODE_ERROR", "Failed to decode: ${e.message}", e.stackTraceToString())
            }
        }

        private fun handleEncodeXML(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
            val xmlContent = call.argument<String>("xmlContent")
            if (xmlContent == null) {
                result.error("INVALID_ARGUMENT", "Missing 'xmlContent' argument", null)
                return
            }

            try {
                val encoder = aXMLEncoder()
                val encodedBytes: ByteArray = encoder.encodeString(this, xmlContent)
                result.success(encodedBytes)
            } catch (e: XmlPullParserException) {
                Log.e("AXML_ENCODE", "XML Parsing Error", e)
                result.error("ENCODE_ERROR", "Invalid XML format: ${e.message}", null)
            } catch (e: Exception) {
                Log.e("AXML_ENCODE", "Generic Error", e)
                result.error("ENCODE_ERROR", "An unexpected error occurred: ${e.message}", null)
            }
        }
        
        private fun handleBuildAndSignApk(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
            try {
                copyAssetToFile("assets/signing/key.pk8", "app_key.pk8")
                copyAssetToFile("assets/signing/cert.pem", "app_cert.pem")
            } catch (e: IOException) {
                result.error("ASSET_ERROR", "Failed to copy signing keys.", e.stackTraceToString())
                return
            }

            val originalApkPath = call.argument<String>("originalApkPath")
            val filesToReplace = call.argument<Map<String, ByteArray>>("filesToReplace")

            if (originalApkPath == null || filesToReplace == null || filesToReplace.isEmpty()) {
                result.error("INVALID_ARGUMENT", "Missing or empty arguments for buildAndSignApk", null)
                return
            }

            val unsignedApk = File.createTempFile("unsigned_", ".apk", cacheDir)
            val signedApk = File.createTempFile("signed_", ".apk", cacheDir)

            try {
                // Call the updated function with the map of files
                addFileToApk(
                    inputFile = File(originalApkPath),
                    outputFile = unsignedApk,
                    filesToAdd = filesToReplace
                )

                val appSigner = AppSigner(context)
                appSigner.sign(unsignedApk, signedApk)
                
                val signedApkBytes = signedApk.readBytes()
                result.success(signedApkBytes)

            } catch (e: Exception) {
                Log.e("BUILD_SIGN_ERROR", "Build/Sign failed", e)
                result.error("SIGN_ERROR", "Failed to build or sign APK: ${e.message}", e.stackTraceToString())
            } finally {
                unsignedApk.delete()
                signedApk.delete()
            }
        }

        private fun handleDebugListAssets(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
            val path = call.argument<String>("path") ?: ""
            try {
                val assetList = assets.list("flutter_assets/$path")
                result.success(assetList?.toList())
            } catch (e: IOException) {
                result.error("DEBUG_FAIL", "Failed to list assets: ${e.message}", null)
            }
        }

        private fun isBinaryXML(file: File): Boolean {
            if (!file.exists() || !file.isFile) return false
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

        @Throws(IOException::class)
        private fun copyAssetToFile(assetName: String, outputFileName: String) {
            val outFile = File(filesDir, outputFileName)
            // Actually if we want to access the flutter assets natively or say bridge, its not direct so I created flutter_assets/(assets_path)
            val realAssetPath = "flutter_assets/$assetName"
            assets.open(realAssetPath).use { inputStream ->
                FileOutputStream(outFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            }
        }

        private fun addFileToApk(inputFile: File, outputFile: File, filesToAdd: Map<String, ByteArray>) {
        // Get the set of file paths we need to replace.
        val replacementPaths = filesToAdd.keys

        ZipInputStream(inputFile.inputStream().buffered()).use { zis ->
            ZipOutputStream(outputFile.outputStream().buffered()).use { zos ->
                val writtenEntries = mutableSetOf<String>()

                // Copy all entries from the original APK, skipping any that are in our replacement map.
                var entry = zis.nextEntry
                while (entry != null) {
                    // If the entry is one of the files we want to replace, skip it.
                    if (replacementPaths.contains(entry.name)) {
                        entry = zis.nextEntry
                        continue
                    }

                    if (entry.isDirectory || writtenEntries.contains(entry.name)) {
                        entry = zis.nextEntry
                        continue
                    }

                    val newEntry = ZipEntry(entry.name)
                    newEntry.method = entry.method
                    if (newEntry.method == ZipEntry.STORED) {
                        newEntry.size = entry.size
                        newEntry.compressedSize = entry.compressedSize
                        newEntry.crc = entry.crc
                    }

                    zos.putNextEntry(newEntry)
                    zis.copyTo(zos)
                    zos.closeEntry()
                    writtenEntries.add(newEntry.name)

                    entry = zis.nextEntry
                }

                // adds all the new/modified files from our map.
                for ((filePath, fileBytes) in filesToAdd) {
                    val newFileEntry = ZipEntry(filePath)
                    zos.putNextEntry(newFileEntry)
                    zos.write(fileBytes)
                    zos.closeEntry()
                }
            }
        }
    }
}