import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visitors_capture/db.dart';
import 'package:visitors_capture/lead.dart';
import 'package:visitors_capture/sync.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LeadDb.dbName = 'test_sync_suite.db'; // own file — suites run in parallel
  });

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

  test('a voice note is uploaded as an audio data URL', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    final tmp = File('${Directory.systemTemp.path}/test-note.m4a');
    await tmp.writeAsBytes([1, 2, 3, 4]);
    await db.insert(Lead.create(phone: '9744187790', audioPath: tmp.path));

    String? audioField;
    final client = MockClient((req) async {
      audioField = (jsonDecode(req.body) as Map)['audio'] as String?;
      return http.Response('{}', 200);
    });

    final result = await syncAll(client: client);
    expect(result.uploaded, 1);
    expect(audioField, startsWith('data:audio/mp4;base64,'));
    expect(audioField!.split(',')[1], base64Encode([1, 2, 3, 4]));
    await tmp.delete();
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
