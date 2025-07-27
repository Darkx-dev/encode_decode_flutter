import 'dart:typed_data';

class ModifiableFile {
  // The path inside the APK (e.g., 'res/xml/appfilter.xml')
  String apkPath;
  
  // The new content for the file
  Uint8List content;

  // The original local path (optional, for reference)
  String? sourcePath;

  ModifiableFile({
    required this.apkPath,
    required this.content,
    this.sourcePath,
  });
}