import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'lead.dart';

class LeadDb {
  LeadDb._();
  static final LeadDb instance = LeadDb._();
  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'leads.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE leads (
          id TEXT PRIMARY KEY, phone TEXT NOT NULL, name TEXT, company TEXT,
          email TEXT, website TEXT, city TEXT, state TEXT, products TEXT, note TEXT,
          tag TEXT, front_path TEXT, back_path TEXT, created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )'''),
    );
  }

  Future<void> insert(Lead l) async =>
      (await _database).insert('leads', l.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  // Any edit re-queues the lead for upload.
  Future<void> update(Lead l) async =>
      (await _database).update('leads', l.copyWith(synced: 0).toMap(), where: 'id=?', whereArgs: [l.id]);

  Future<List<Lead>> all() async =>
      (await _database).query('leads', orderBy: 'created_at DESC').then((r) => r.map(Lead.fromMap).toList());

  Future<List<Lead>> unsynced() async =>
      (await _database).query('leads', where: 'synced=0', orderBy: 'created_at').then((r) => r.map(Lead.fromMap).toList());

  Future<void> markSynced(String id) async =>
      (await _database).update('leads', {'synced': 1}, where: 'id=?', whereArgs: [id]);

  Future<bool> phoneExists(String phone) async =>
      (await _database).query('leads', where: 'phone=?', whereArgs: [phone], limit: 1).then((r) => r.isNotEmpty);

  // Test helper: drop all rows.
  Future<void> resetForTest() async => (await _database).delete('leads');
}
