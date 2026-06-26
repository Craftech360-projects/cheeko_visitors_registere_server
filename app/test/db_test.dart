import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:visitors_capture/db.dart';
import 'package:visitors_capture/lead.dart';

void main() {
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('insert then unsynced returns it; markSynced clears it', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    final lead = Lead.create(phone: '9744187790', name: 'Rahul');
    await db.insert(lead);

    var pending = await db.unsynced();
    expect(pending.length, 1);
    expect(pending.first.name, 'Rahul');

    await db.markSynced(lead.id);
    pending = await db.unsynced();
    expect(pending, isEmpty);
  });

  test('editing a synced lead resets it to unsynced', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    final lead = Lead.create(phone: '9000000000', name: 'A');
    await db.insert(lead);
    await db.markSynced(lead.id);

    await db.update(lead.copyWith(name: 'A edited'));
    final pending = await db.unsynced();
    expect(pending.length, 1);
    expect(pending.first.name, 'A edited');
  });

  test('phoneExists detects a locally-captured number', () async {
    final db = LeadDb.instance;
    await db.resetForTest();
    await db.insert(Lead.create(phone: '9811111111'));
    expect(await db.phoneExists('9811111111'), isTrue);
    expect(await db.phoneExists('9822222222'), isFalse);
  });
}
