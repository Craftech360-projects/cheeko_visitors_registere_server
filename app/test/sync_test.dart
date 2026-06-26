import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visitors_capture/db.dart';
import 'package:visitors_capture/lead.dart';
import 'package:visitors_capture/sync.dart';

void main() {
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('syncAll uploads unsynced leads and marks them synced', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    await db.insert(Lead.create(phone: '9744187790', name: 'A'));
    await db.insert(Lead.create(phone: '9811111111', name: 'B'));

    final seen = <String>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, Object?>;
      seen.add(body['phone'] as String);
      return http.Response(jsonEncode({'id': body['id'], 'wa_phone': 'x'}), 200);
    });

    final result = await syncAll(client: client);
    expect(result.uploaded, 2);
    expect(result.failed, 0);
    expect(seen.toSet(), {'9744187790', '9811111111'});
    expect(await db.unsynced(), isEmpty);
  });

  test('a failed upload leaves that lead unsynced', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    await db.insert(Lead.create(phone: '9744187790'));
    final client = MockClient((req) async => http.Response('boom', 502));
    final result = await syncAll(client: client);
    expect(result.uploaded, 0);
    expect(result.failed, 1);
    expect((await db.unsynced()).length, 1);
  });
}
