import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// One voice note per lead, saved as `<docs>/<id>-audio.m4a` (AAC).
class LeadRecorder {
  final _rec = AudioRecorder();
  bool get isRecording => _recording;
  bool _recording = false;

  /// Starts recording; returns false if the mic permission was denied.
  Future<bool> start(String leadId) async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getApplicationDocumentsDirectory();
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: p.join(dir.path, '$leadId-audio.m4a'),
    );
    _recording = true;
    return true;
  }

  /// Stops and returns the file path (null if nothing was recorded).
  Future<String?> stop() async {
    _recording = false;
    return _rec.stop();
  }

  Future<void> dispose() => _rec.dispose();
}

Future<String> audioToDataUrl(String path) async {
  final bytes = await File(path).readAsBytes();
  return 'data:audio/mp4;base64,${base64Encode(bytes)}';
}
