import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _picker = ImagePicker();

Future<String?> capturePhoto(String id, String side) async {
  final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
  if (shot == null) return null;
  final raw = await shot.readAsBytes();
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  // Downscale longest edge to 1280, re-encode JPEG q70.
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: 1280)
      : img.copyResize(decoded, height: 1280);
  final jpg = img.encodeJpg(resized, quality: 70);
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, '$id-$side.jpg');
  await File(path).writeAsBytes(jpg);
  return path;
}

Future<String> fileToDataUrl(String path) async {
  final bytes = await File(path).readAsBytes();
  return 'data:image/jpeg;base64,${base64Encode(bytes)}';
}
