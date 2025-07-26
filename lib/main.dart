import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APK XML Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('my_android_plugin/decode');

  final TextEditingController _xmlTextController = TextEditingController();
  String? _originalFilePath;
  String _status = 'Welcome! Open a binary XML file to start.';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _xmlTextController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isDenied) {
        setState(() {
          _status = 'Storage permission is required to open and save files.';
        });
      }
    }
  }

  Future<void> _pickAndDecodeBinaryXml() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _originalFilePath = path;
          _status = 'Decoding file...';
        });

        final String decodedXml = await platform.invokeMethod(
          'decodeBinaryAXML',
          {'path': path},
        );

        setState(() {
          _xmlTextController.text = decodedXml;
          _status = 'File decoded successfully. You can now edit the content.';
        });
      } else {
        setState(() {
          _status = 'File selection cancelled.';
        });
      }
    } on PlatformException catch (e) {
      _showError('Failed to decode file: ${e.message}');
    }
  }

  Future<void> _encodeAndSaveXml() async {
    if (_xmlTextController.text.trim().isEmpty) {
      _showError('XML content is empty. Nothing to save.');
      return;
    }

    try {
      setState(() => _status = 'Encoding XML content...');

      final Uint8List? encodedData = await platform.invokeMethod<Uint8List>(
        'encodeXml',
        {'xmlContent': _xmlTextController.text},
      );

      if (encodedData == null) {
        _showError('Encoding failed: Native code returned no data.');
        return;
      }

      setState(() => _status = 'Please choose a location to save the file.');

      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Encoded XML As...',
        fileName: 'encoded_output.xml',
        bytes: encodedData,
      );

      setState(() {
        _status = savePath != null
            ? 'File saved successfully.'
            : 'Save operation cancelled.';
      });
    } on PlatformException catch (e) {
      _showError('Encoding failed: ${e.message}');
    }
  }

  Future<void> _buildAndSignApk() async {
    if (_xmlTextController.text.trim().isEmpty) {
      _showError('XML content is empty. Cannot build APK.');
      return;
    }

    try {
      setState(() => _status = 'Please select the base APK file to modify...');
      FilePickerResult? baseApkResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );
      if (baseApkResult == null || baseApkResult.files.single.path == null) {
        setState(() => _status = 'Base APK selection cancelled.');
        return;
      }
      final String originalApkPath = baseApkResult.files.single.path!;

     
      setState(() => _status = 'Encoding XML content...');
      final Uint8List? encodedXmlBytes = await platform.invokeMethod<Uint8List>(
        'encodeXml',
        {'xmlContent': _xmlTextController.text},
      );
      if (encodedXmlBytes == null) {
        throw PlatformException(
            code: 'ENCODE_FAIL', message: 'Encoding XML returned null.');
      }

      setState(() => _status = 'Building and signing APK... This may take a moment.');
      final Uint8List? signedApkBytes = await platform.invokeMethod<Uint8List>(
        'buildAndSignApk',
        {
          'originalApkPath': originalApkPath,
          'xmlFileName': 'my_edited_config.xml', // This shit gonna be saved with this name whatever u gonna specify in the app, yes you dont need archive package anymore for packing
          'xmlBytes': encodedXmlBytes,
        },
      );
      if (signedApkBytes == null) {
        throw PlatformException(
            code: 'SIGN_FAIL', message: 'Building/signing returned null.');
      }

      setState(() => _status = 'Please choose where to save the signed APK...');
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Signed APK As...',
        fileName: 'signed-output.apk',
        bytes: signedApkBytes,
      );

      setState(() {
        _status = savePath != null
            ? 'Signed APK saved successfully!'
            : 'Save operation cancelled.';
      });
    } on PlatformException catch (e) {
      _showError('Build/Sign failed: ${e.message}');
      debugPrint(e.details);
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    }
  }
  
  Future<void> _debugListAssets() async {
    try {
      final List<dynamic>? assets = await platform.invokeMethod(
        'debugListAssets',
        {'path': 'assets/signing'}, // Check inside the signing folder
      );
      debugPrint('--- ASSET DEBUG ---');
      if (assets != null && assets.isNotEmpty) {
        debugPrint('Found assets in "flutter_assets/assets/signing":');
        for (var asset in assets) {
          debugPrint('- $asset');
        }
        _showSuccess('Found assets: ${assets.join(', ')}');
      } else {
        debugPrint('!!! Could not find assets in "flutter_assets/assets/signing"');
        _showError('Could not find assets. Check Logcat for details.');
      }
    } on PlatformException catch (e) {
      _showError('Asset debug failed: ${e.message}');
    }
  }

  void _showError(String message) {
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ));
  }
  
  void _showSuccess(String message) {
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('APK XML Editor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open XML'),
                  onPressed: _pickAndDecodeBinaryXml,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_as),
                  label: const Text('Save XML As...'),
                  onPressed: _encodeAndSaveXml,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.build_circle),
                  label: const Text('Build & Sign APK'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _buildAndSignApk,
                ),
                 ElevatedButton.icon(
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Debug Assets'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                  ),
                  onPressed: _debugListAssets,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            if (_originalFilePath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Editing: ${_originalFilePath!.split('/').last}',
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _xmlTextController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Decoded XML content will appear here...',
                ),
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
          ],
        ),
      ),
    );
  }
}