import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

/// Saves a generated report or label sheet where the user can find it.
///
/// `file_saver` puts the bytes in Downloads on desktop and triggers the
/// browser's own save on web, so one call covers the Supervisor's PC and the
/// table tablet alike.
Future<String> saveBytes({
  required String filename,
  required Uint8List bytes,
  required String mime,
}) async {
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot + 1) : 'bin';
  return FileSaver.instance.saveFile(
    name: stem,
    bytes: bytes,
    fileExtension: ext,
    mimeType: _mime(ext, mime),
  );
}

MimeType _mime(String ext, String fallback) => switch (ext.toLowerCase()) {
      'xlsx' => MimeType.microsoftExcel,
      'csv' => MimeType.csv,
      'pdf' => MimeType.pdf,
      _ => MimeType.other,
    };
