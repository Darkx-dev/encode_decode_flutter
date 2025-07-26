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
      title: 'Binary XML Editor',
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
  String? _binaryXmlPath;
  String _status = 'Please open a binary XML file.';

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  @override
  void dispose() {
    _xmlTextController.dispose();
    super.dispose();
  }

  Future<void> _initPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        setState(() {
          _status = 'Storage permission is required.';
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
          _binaryXmlPath = path;
          _status = 'Decoding...';
        });

        final String decodedXml = await platform.invokeMethod(
          'decodeBinaryAXML',
          {'path': path},
        );

        debugPrint('Decoded XML:\n$decodedXml');

        setState(() {
          if (decodedXml.trim().isEmpty) {
            _xmlTextController.text = '';
            _status = 'Decoded content is empty or failed.';
          } else {
            _xmlTextController.text = decodedXml;
            _status = 'File decoded successfully.';
          }
        });
      } else {
        setState(() {
          _status = 'File selection cancelled.';
        });
      }
    } on PlatformException catch (e) {
      debugPrint('PlatformException: ${e.message}');
      setState(() {
        _status = "Failed to decode file: '${e.message}'.";
      });
    }
  }

  Future<void> _encodeAndSaveXml() async {
    if (_xmlTextController.text.trim().isEmpty) {
      setState(() => _status = 'No content to save.');
      return;
    }

    try {
      setState(() => _status = 'Encoding content...');

      final Uint8List? encodedData = await platform.invokeMethod<Uint8List>(
        'encodeXml',
        {'xmlContent': _xmlTextController.text},
      );

      if (encodedData == null) {
        setState(() => _status = 'Encoding failed: Received no data.');
        return;
      }

      setState(() => _status = 'Waiting for you to choose a save location...');

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save encoded XML as...',
        fileName: 'encoded_output.xml',
        bytes: encodedData,
      );

      setState(() => _status = 'File save dialog closed.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File save operation complete.')),
        );
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Encoding failed: ${e.message}');
    } catch (e) {
      setState(() => _status = 'An error occurred: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Binary XML Editor'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Binary XML'),
                  onPressed: _pickAndDecodeBinaryXml,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save As'),
                  onPressed: _encodeAndSaveXml,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_status, style: TextStyle(color: Colors.grey[700])),
            ),
            if (_binaryXmlPath != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Editing: $_binaryXmlPath',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'XML Content:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _xmlTextController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Decoded XML appears here...',
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
