import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'db.dart';
import 'lead.dart';
import 'photos.dart';

class SyncResult {
  final int uploaded, failed;
  const SyncResult(this.uploaded, this.failed);
}

Future<Map<String, Object?>> leadToPayload(Lead l) async => {
      'id': l.id, 'phone': l.phone, 'name': l.name, 'company': l.company,
      'email': l.email, 'website': l.website, 'city': l.city, 'state': l.state,
      'products': l.products, 'note': l.note, 'tag': l.tag,
      'created_at': l.createdAt,
      if (l.frontPath != null) 'frontPhoto': await fileToDataUrl(l.frontPath!),
      if (l.backPath != null) 'backPhoto': await fileToDataUrl(l.backPath!),
    };

// Upload every unsynced lead, one request each. Resumable: a failure leaves
// that lead unsynced for the next press. Idempotent server-side (upsert on id).
Future<SyncResult> syncAll({http.Client? client, void Function(int, int)? onProgress}) async {
  final c = client ?? http.Client();
  final pending = await LeadDb.instance.unsynced();
  var uploaded = 0, failed = 0;
  for (var i = 0; i < pending.length; i++) {
    final lead = pending[i];
    try {
      final res = await c.post(
        Uri.parse('${Config.serverUrl}/api/leads'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(await leadToPayload(lead)),
      );
      if (res.statusCode == 200) {
        await LeadDb.instance.markSynced(lead.id);
        uploaded++;
      } else {
        failed++;
      }
    } catch (_) {
      failed++;
    }
    onProgress?.call(i + 1, pending.length);
  }
  if (client == null) c.close();
  return SyncResult(uploaded, failed);
}
