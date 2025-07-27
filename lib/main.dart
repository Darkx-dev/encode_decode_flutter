import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_android_plugin/modifiable.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advanced APK Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
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

  // --- State Variables ---
  String? _apkPath;
  final List<ModifiableFile> _filesToModify = [];
  final List<String> _logMessages = [];
  final ScrollController _logScrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _log('Welcome! Load a base APK to begin.');
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  // --- Helper Functions ---
  void _log(String message, {bool isError = false}) {
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      _logMessages.add('[$timestamp] ${isError ? "ERROR: " : ""}$message');
    });
    // Auto-scroll to the bottom of the log
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
    debugPrint(message);
  }

  void _setLoading(bool loading) {
    setState(() {
      _isLoading = loading;
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isDenied) {
        _log('Storage permission is required to open and save files.', isError: true);
      }
    }
  }

  // --- Core Logic Functions ---
  Future<void> _loadBaseApk() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _apkPath = result.files.single.path;
        _filesToModify.clear(); // Clear old files when loading a new APK
      });
      _log('Loaded base APK: ${_apkPath!.split('/').last}');
    } else {
      _log('APK selection cancelled.');
    }
  }

  Future<void> _addFileToModify() async {
    final targetPath = await _showTextInputDialog(
      title: 'APK Target Path',
      hint: 'e.g., res/xml/appfilter.xml or assets/my_file.txt',
    );

    if (targetPath == null || targetPath.trim().isEmpty) {
      _log('Target path input cancelled.');
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsBytes();
      
      // For XML files, let's also try to decode them for easier editing.
      if (targetPath.endsWith('.xml')) {
          try {
              final String decodedXml = await platform.invokeMethod(
                'decodeBinaryAXML',
                {'path': file.path},
              );
              final updatedContent = Uint8List.fromList(utf8.encode(decodedXml));
               setState(() {
                _filesToModify.add(ModifiableFile(
                  apkPath: targetPath,
                  content: updatedContent,
                  sourcePath: file.path,
                ));
              });
              _log('Added and decoded: ${file.path.split('/').last} -> $targetPath');
              return;

          } catch (e) {
             _log('File is not a binary XML, adding as-is. Error: $e');
          }
      }
      
      setState(() {
        _filesToModify.add(ModifiableFile(
          apkPath: targetPath,
          content: content,
          sourcePath: file.path,
        ));
      });
      _log('Added: ${file.path.split('/').last} -> $targetPath');
    } else {
      _log('File selection cancelled.');
    }
  }
  
  Future<void> _editFileContent(int index) async {
    final file = _filesToModify[index];
    // Simple check if it's likely text.
    // A more robust check might try/catch utf8.decode.
    if (!file.apkPath.endsWith('.png') && !file.apkPath.endsWith('.jpg')) {
      final controller = TextEditingController(text: utf8.decode(file.content, allowMalformed: true));
      final newContent = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit ${file.apkPath.split('/').last}'),
          content: TextField(
            controller: controller,
            maxLines: 15,
            expands: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
          ],
        ),
      );

      if (newContent != null) {
        setState(() {
          file.content = Uint8List.fromList(utf8.encode(newContent));
        });
        _log('Updated content for ${file.apkPath}');
      }
    } else {
       _log('Cannot edit binary file "${file.apkPath}" in text editor.', isError: true);
    }
  }


  Future<void> _buildAndSignApk() async {
    if (_apkPath == null) {
      _log('Please load a base APK first.', isError: true);
      return;
    }
    if (_filesToModify.isEmpty) {
      _log('Please add at least one file to modify.', isError: true);
      return;
    }

    _setLoading(true);
    _log('Starting build process...');

    try {
      // Create the map of files to replace/add
      final Map<String, Uint8List> filesToReplace = {};
      
      for (final file in _filesToModify) {
        // If it's an XML file, re-encode it to binary AXML
        if (file.apkPath.endsWith('.xml')) {
           _log('Encoding ${file.apkPath} to binary AXML...');
           try {
              final String currentContent = utf8.decode(file.content);
              final Uint8List? encodedBytes = await platform.invokeMethod<Uint8List>(
                'encodeXml',
                {'xmlContent': currentContent},
              );
              if (encodedBytes == null) throw Exception('XML encoding returned null.');
              filesToReplace[file.apkPath] = encodedBytes;
           } catch(e) {
              _log('Failed to encode ${file.apkPath}. Error: $e', isError: true);
              _setLoading(false);
              return;
           }
        } else {
          filesToReplace[file.apkPath] = file.content;
        }
      }
      _log('All files prepared. Repackaging and signing...');

      final Uint8List? signedApkBytes =
          await platform.invokeMethod<Uint8List>(
        'buildAndSignApk',
        {
          'originalApkPath': _apkPath!,
          'filesToReplace': filesToReplace,
        },
      );

      if (signedApkBytes == null) {
        throw PlatformException(code: 'SIGN_FAIL', message: 'Building/signing returned null.');
      }

      _log('APK signed successfully! Please choose a save location.');
      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Signed APK As...',
        fileName: 'signed-output.apk',
        bytes: signedApkBytes,
      );

      if (savePath != null) {
        _log('Signed APK saved to: $savePath');
      } else {
        _log('Save operation cancelled.');
      }
    } on PlatformException catch (e) {
      _log('Build/Sign failed: ${e.message}', isError: true);
      debugPrint(e.details);
    } catch (e) {
      _log('An unexpected error occurred: $e', isError: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<String?> _showTextInputDialog({required String title, required String hint}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('OK')),
        ],
      ),
    );
  }

  // --- Widget Build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced APK Editor')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _buildApkLoaderCard(),
                const SizedBox(height: 12),
                _buildFilesToModifyCard(),
                const SizedBox(height: 12),
                _buildConsoleCard(),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildApkLoaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Step 1: Load Base APK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.android),
              title: Text(_apkPath?.split('/').last ?? 'No APK Loaded'),
              subtitle: Text(_apkPath ?? '...'),
              dense: true,
            ),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Load APK'),
                onPressed: _isLoading ? null : _loadBaseApk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesToModifyCard() {
    return Expanded(
      flex: 3,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Step 2: Add/Edit Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_filesToModify.isEmpty)
                const Expanded(child: Center(child: Text('No files added yet.')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _filesToModify.length,
                    itemBuilder: (context, index) {
                      final file = _filesToModify[index];
                      return Card(
                        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                        child: ListTile(
                          leading: const Icon(Icons.description),
                          title: Text(file.apkPath, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Size: ${file.content.lengthInBytes} bytes'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit), onPressed: _isLoading ? null : () => _editFileContent(index)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _isLoading ? null : () => setState(() => _filesToModify.removeAt(index))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add File'),
                    onPressed: _isLoading || _apkPath == null ? null : _addFileToModify,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.build_circle),
                    label: const Text('Build & Sign'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: _isLoading || _apkPath == null || _filesToModify.isEmpty ? null : _buildAndSignApk,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsoleCard() {
    return Expanded(
      flex: 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Console Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => setState(() => _logMessages.clear()), icon: const Icon(Icons.delete_sweep))
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700)
                  ),
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: _logMessages.length,
                    itemBuilder: (context, index) {
                      final log = _logMessages[index];
                      return Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: log.contains('ERROR:') ? Colors.redAccent : Colors.lightGreenAccent,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}