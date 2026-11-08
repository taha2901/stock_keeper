import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../core/db.dart';

/// Asks where to save and writes the bytes. Returns false if the user cancelled.
Future<bool> saveBytes(String fileName, Uint8List bytes, {String? initialDirectory}) async =>
    await FilePicker.saveFile(fileName: fileName, bytes: bytes, dialogTitle: 'حفظ الملف', initialDirectory: initialDirectory) != null;

/// Opens a file picker and returns the chosen file's bytes (null if cancelled).
Future<Uint8List?> pickBytes({List<String>? extensions, String? initialDirectory}) async {
  final files = await FilePicker.pickFiles(
    initialDirectory: initialDirectory,
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  return files.isEmpty ? null : files.first.readAsBytes();
}

/// Picks one file and returns its name and bytes (null if cancelled).
Future<({String name, Uint8List bytes})?> pickNamed({List<String>? extensions}) async {
  final files = await FilePicker.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

/// Lets the user choose an image and copies it into the app's attachments folder.
Future<String?> pickAttachment() async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  final f = files.first;
  final ext = p.extension(f.name).isEmpty ? '.jpg' : p.extension(f.name);
  final dest = p.join(AppDb.attachmentsDir, '${DateTime.now().millisecondsSinceEpoch}$ext');
  await File(dest).writeAsBytes(await f.readAsBytes());
  return dest;
}
