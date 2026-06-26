# Flutter Capture App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter app that captures leads fully offline (local SQLite + on-device photos) and uploads unsynced leads to the cloud server on a manual Sync button.

**Architecture:** Local-first. Capture writes to sqflite with `synced=0` and a client-generated UUID; photos are downscaled and saved as files. The Sync button loops over `synced=0` rows and POSTs each to `{SERVER_URL}/api/leads` (the server plan's endpoint), marking `synced=1` on HTTP 200. Upload-only — the app never pulls; review happens on the web dashboard.

**Tech Stack:** Flutter (stable), `sqflite`, `path_provider`, `image_picker`, `image`, `http`, `uuid`. Targets the server from `docs/superpowers/plans/2026-06-26-server-supabase-gateway.md`.

## Global Constraints

- App lives in `app/` inside this repo (`d:\visitors_register\app`).
- `id` is a UUID v4 generated at capture; it is the server upsert key.
- Phone is the only required field. The app does **local** dedup (warn if the phone is already in the local DB); it does not dedup across devices.
- `synced` lifecycle: created `0`; set to `1` on a successful upload; **reset to `0` on any edit**. Sync only ever touches `synced=0` rows.
- Photos downscaled to ~1280px longest edge, JPEG quality ~70, before save/upload (keeps payloads small, matching the web capture).
- Server URL is a single config constant in `lib/config.dart`, overridable in a Settings field.
- Upload payload matches the server contract: `{ id, phone, name, company, email, website, city, state, products, note, tag, frontPhoto, backPhoto, created_at }` where photos are base64 **data URLs** (`data:image/jpeg;base64,...`) or omitted/null.

---

### Task 1: Scaffold the Flutter project

**Files:**
- Create: `app/` (Flutter project), `app/pubspec.yaml`

**Interfaces:**
- Produces: a runnable Flutter app skeleton with the dependencies installed.

- [ ] **Step 1: Create the project**

Run from `d:\visitors_register`:
```bash
flutter create --org com.craftech360 --project-name visitors_capture app
```
Expected: `app/` created, `flutter doctor` clean enough to build.

- [ ] **Step 2: Add dependencies**

Run:
```bash
cd app && flutter pub add sqflite path_provider image_picker image http uuid path
```
Expected: these appear under `dependencies:` in `app/pubspec.yaml`.

- [ ] **Step 3: Verify it builds**

Run: `cd app && flutter analyze`
Expected: "No issues found!" (the default counter app).

- [ ] **Step 4: Commit**

```bash
git add app
git commit -m "scaffold: Flutter capture app with deps"
```

---

### Task 2: Lead model + local database (`app/lib/db.dart`, `app/lib/lead.dart`)

**Files:**
- Create: `app/lib/lead.dart`, `app/lib/db.dart`
- Test: `app/test/db_test.dart`

**Interfaces:**
- Produces:
  - `class Lead` — fields `id, phone, name, company, email, website, city, state, products, note, tag, frontPath, backPath, createdAt, synced`; `toMap()` / `Lead.fromMap()`.
  - `LeadDb.instance` — `insert(Lead)`, `update(Lead)` (resets `synced=0`), `all()`, `unsynced()`, `markSynced(id)`, `phoneExists(phone)`.

- [ ] **Step 1: Write the failing test**

Create `app/test/db_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
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
```

Add the test-only dep: `cd app && flutter pub add --dev sqflite_common_ffi`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/db_test.dart`
Expected: FAIL — `db.dart` / `lead.dart` not found.

- [ ] **Step 3: Write `app/lib/lead.dart`**

```dart
import 'package:uuid/uuid.dart';

class Lead {
  final String id;
  final String phone;
  final String? name, company, email, website, city, state, products, note, tag;
  final String? frontPath, backPath;
  final String createdAt;
  final int synced;

  Lead({
    required this.id, required this.phone, this.name, this.company, this.email,
    this.website, this.city, this.state, this.products, this.note, this.tag,
    this.frontPath, this.backPath, required this.createdAt, this.synced = 0,
  });

  factory Lead.create({
    required String phone, String? name, String? company, String? email,
    String? website, String? city, String? state, String? products, String? note,
    String? tag, String? frontPath, String? backPath,
  }) =>
      Lead(
        id: const Uuid().v4(), phone: phone, name: name, company: company,
        email: email, website: website, city: city, state: state, products: products,
        note: note, tag: tag, frontPath: frontPath, backPath: backPath,
        createdAt: DateTime.now().toUtc().toIso8601String(), synced: 0,
      );

  Lead copyWith({
    String? phone, String? name, String? company, String? email, String? website,
    String? city, String? state, String? products, String? note, String? tag,
    String? frontPath, String? backPath, int? synced,
  }) =>
      Lead(
        id: id, phone: phone ?? this.phone, name: name ?? this.name,
        company: company ?? this.company, email: email ?? this.email,
        website: website ?? this.website, city: city ?? this.city,
        state: state ?? this.state, products: products ?? this.products,
        note: note ?? this.note, tag: tag ?? this.tag,
        frontPath: frontPath ?? this.frontPath, backPath: backPath ?? this.backPath,
        createdAt: createdAt, synced: synced ?? this.synced,
      );

  Map<String, Object?> toMap() => {
        'id': id, 'phone': phone, 'name': name, 'company': company, 'email': email,
        'website': website, 'city': city, 'state': state, 'products': products,
        'note': note, 'tag': tag, 'front_path': frontPath, 'back_path': backPath,
        'created_at': createdAt, 'synced': synced,
      };

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
        id: m['id'] as String, phone: m['phone'] as String, name: m['name'] as String?,
        company: m['company'] as String?, email: m['email'] as String?,
        website: m['website'] as String?, city: m['city'] as String?,
        state: m['state'] as String?, products: m['products'] as String?,
        note: m['note'] as String?, tag: m['tag'] as String?,
        frontPath: m['front_path'] as String?, backPath: m['back_path'] as String?,
        createdAt: m['created_at'] as String, synced: (m['synced'] as int?) ?? 0,
      );
}
```

- [ ] **Step 4: Write `app/lib/db.dart`**

```dart
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
```

(The import in the model is `package:visitors_capture/...` — match the `--project-name` from Task 1. If you chose a different name, update the test imports.)

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/db_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/lead.dart app/lib/db.dart app/test/db_test.dart app/pubspec.yaml
git commit -m "feat: Lead model + local sqflite store with synced lifecycle"
```

---

### Task 3: Photo capture + downscale helper (`app/lib/photos.dart`)

**Files:**
- Create: `app/lib/photos.dart`

**Interfaces:**
- Produces:
  - `Future<String?> capturePhoto(String id, String side)` — opens the camera, downscales, saves `<docs>/<id>-<side>.jpg`, returns the path (or null if cancelled).
  - `Future<String> fileToDataUrl(String path)` — `data:image/jpeg;base64,...` for upload.

- [ ] **Step 1: Write `app/lib/photos.dart`**

```dart
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
```

- [ ] **Step 2: Verify it analyzes**

Run: `cd app && flutter analyze lib/photos.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/photos.dart
git commit -m "feat: camera capture + downscale to data URL"
```

---

### Task 4: Config + sync service (`app/lib/config.dart`, `app/lib/sync.dart`)

**Files:**
- Create: `app/lib/config.dart`, `app/lib/sync.dart`
- Test: `app/test/sync_test.dart`

**Interfaces:**
- Consumes: `LeadDb`, `Lead`, `fileToDataUrl`.
- Produces:
  - `Config.serverUrl` (mutable, default constant).
  - `Future<Map<String,Object?>> leadToPayload(Lead)` — JSON body incl. base64 photos.
  - `Future<SyncResult> syncAll({http.Client? client, void Function(int done,int total)? onProgress})` — loops unsynced, POSTs each, marks synced on 200; returns `SyncResult(uploaded, failed)`.

- [ ] **Step 1: Write the failing test (fake HTTP, no network)**

Create `app/test/sync_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/sync_test.dart`
Expected: FAIL — `sync.dart` not found.

- [ ] **Step 3: Write `app/lib/config.dart`**

```dart
class Config {
  // Default to the deployed droplet; editable from the Settings screen.
  static String serverUrl = 'https://your-droplet-host';
}
```

- [ ] **Step 4: Write `app/lib/sync.dart`**

```dart
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/sync_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/config.dart app/lib/sync.dart app/test/sync_test.dart
git commit -m "feat: per-lead resumable sync service with config server URL"
```

---

### Task 5: Capture screen (`app/lib/capture_screen.dart`)

**Files:**
- Create: `app/lib/capture_screen.dart`

**Interfaces:**
- Consumes: `LeadDb`, `Lead.create`, `capturePhoto`.
- Produces: `CaptureScreen` (StatefulWidget) — form + photo buttons + Save.

- [ ] **Step 1: Write `app/lib/capture_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';
import 'lead.dart';
import 'photos.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in _fields) k: TextEditingController()};
  static const _fields = ['phone', 'name', 'company', 'email', 'website', 'city', 'state', 'products', 'note'];
  final _id = const Uuid().v4(); // pre-allocate so photos share the lead id
  String? _frontPath, _backPath;
  bool _saving = false;

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  Future<void> _shoot(String side) async {
    final path = await capturePhoto(_id, side);
    if (path != null) setState(() => side == 'front' ? _frontPath = path : _backPath = path);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final phone = _c['phone']!.text.trim();
    if (await LeadDb.instance.phoneExists(phone) && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Already captured'),
          content: const Text('This number is already on this phone. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _saving = true);
    final lead = Lead(
      id: _id, phone: phone, name: _t('name'), company: _t('company'), email: _t('email'),
      website: _t('website'), city: _t('city'), state: _t('state'), products: _t('products'),
      note: _t('note'), frontPath: _frontPath, backPath: _backPath,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await LeadDb.instance.insert(lead);
    if (mounted) Navigator.pop(context, true);
  }

  String? _t(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New lead')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _c['phone'],
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
              ),
              for (final k in _fields.where((k) => k != 'phone'))
                TextFormField(controller: _c[k], decoration: InputDecoration(labelText: k[0].toUpperCase() + k.substring(1))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _shoot('front'), icon: const Icon(Icons.camera_alt), label: Text(_frontPath == null ? 'Front photo' : 'Front ✓'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => _shoot('back'), icon: const Icon(Icons.camera_alt), label: Text(_backPath == null ? 'Back photo' : 'Back ✓'))),
              ]),
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save lead')),
            ],
          ),
        ),
      );
}
```

- [ ] **Step 2: Verify analyze**

Run: `cd app && flutter analyze lib/capture_screen.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/capture_screen.dart
git commit -m "feat: capture screen with local dedup + photo capture"
```

---

### Task 6: Leads list + Sync button + Settings (`app/lib/main.dart`, `app/lib/settings_screen.dart`)

**Files:**
- Modify: `app/lib/main.dart` (replace the scaffold counter app)
- Create: `app/lib/settings_screen.dart`

**Interfaces:**
- Consumes: `LeadDb`, `CaptureScreen`, `syncAll`, `Config`.
- Produces: `LeadsScreen` (home) — list with synced badges, a Sync action, a + to capture, a gear to Settings.

- [ ] **Step 1: Write `app/lib/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'config.dart';

class SettingsScreen extends StatelessWidget {
  SettingsScreen({super.key});
  final _ctrl = TextEditingController(text: Config.serverUrl);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _ctrl, decoration: const InputDecoration(labelText: 'Server URL')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () { Config.serverUrl = _ctrl.text.trim(); Navigator.pop(context); },
              child: const Text('Save'),
            ),
          ]),
        ),
      );
}
```

- [ ] **Step 2: Replace `app/lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'capture_screen.dart';
import 'db.dart';
import 'lead.dart';
import 'settings_screen.dart';
import 'sync.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Visitors Capture',
        theme: ThemeData(colorSchemeSeed: const Color(0xFFE96B2C), useMaterial3: true),
        home: const LeadsScreen(),
      );
}

class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  List<Lead> _leads = [];
  bool _syncing = false;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { _leads = await LeadDb.instance.all(); if (mounted) setState(() {}); }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final r = await syncAll(onProgress: (d, t) {});
    await _load();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded ${r.uploaded}, failed ${r.failed}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _leads.where((l) => l.synced == 0).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen()))),
          _syncing
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton.icon(onPressed: pending == 0 ? null : _sync, icon: const Icon(Icons.cloud_upload), label: Text('Sync ($pending)')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _leads.isEmpty
            ? const Center(child: Text('No leads yet. Tap + to add one.'))
            : ListView.separated(
                itemCount: _leads.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final l = _leads[i];
                  return ListTile(
                    title: Text(l.name?.isNotEmpty == true ? l.name! : l.phone),
                    subtitle: Text([l.company, l.phone].where((s) => s?.isNotEmpty == true).join(' · ')),
                    trailing: Icon(l.synced == 1 ? Icons.cloud_done : Icons.cloud_off,
                        color: l.synced == 1 ? Colors.green : Colors.grey),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CaptureScreen()));
          if (added == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify analyze + tests still green**

Run: `cd app && flutter analyze && flutter test`
Expected: no analyzer issues; all unit tests pass.

- [ ] **Step 4: Manual end-to-end (device/emulator + running server)**

Start the server (`npm start` with Supabase `.env`), set the app's Settings → Server URL to the reachable host, then: add a lead with a photo → it shows with a grey "cloud off" icon → tap Sync → snackbar "Uploaded 1, failed 0", icon turns green → confirm the row + photo in Supabase and on `/dashboard`.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart app/lib/settings_screen.dart
git commit -m "feat: leads list, Sync button, settings screen"
```

---

## Self-Review

- **Spec coverage:** local-first capture (Tasks 2,5) ✓; UUID id at capture (Task 2) ✓; downscale photos (Task 3) ✓; per-lead resumable sync, mark synced on 200 (Task 4) ✓; failure leaves lead pending (Task 4 test) ✓; synced resets on edit (Task 2 `update`) ✓; local dedup warning (Task 5) ✓; upload-only, no pull (no GET of server leads anywhere) ✓; server URL config (Tasks 4,6) ✓; payload matches server contract incl. base64 data-URL photos (Task 4 `leadToPayload`) ✓.
- **Type consistency:** `Lead.id` is a `String` UUID throughout; payload keys `frontPhoto`/`backPhoto` match the server's `b.frontPhoto`/`b.backPhoto`; `created_at` sent and accepted server-side.
- **Placeholders:** none — full Dart in every code step.
- **Note for executor:** Android needs camera permission — `image_picker` handles the runtime prompt, but confirm `CAMERA` usage on iOS via `NSCameraUsageDescription` in `app/ios/Runner/Info.plist` if you target iOS.
