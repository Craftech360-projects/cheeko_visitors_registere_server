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
        title: 'LeadSnap',
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

  String _initials(Lead l) {
    final name = l.name?.isNotEmpty == true ? l.name! : l.phone;
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static const _avatarPalette = [
    Color(0xFFE57373), // red
    Color(0xFF64B5F6), // blue
    Color(0xFF81C784), // green
    Color(0xFFFFB74D), // orange
    Color(0xFFBA68C8), // purple
    Color(0xFF4DB6AC), // teal
    Color(0xFFF06292), // pink
    Color(0xFF90A4AE), // blue-grey
  ];

  Color _avatarColor(Lead l) {
    final name = l.name?.isNotEmpty == true ? l.name! : l.phone;
    if (name.isEmpty) return _avatarPalette[0];
    return _avatarPalette[name.codeUnitAt(0) % _avatarPalette.length];
  }

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
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _leads.length,
                itemBuilder: (_, i) {
                  final l = _leads[i];
                  final displayName = l.name?.isNotEmpty == true ? l.name! : l.phone;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: () async {
                        final updated = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => CaptureScreen(lead: l)),
                        );
                        if (updated == true) _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: _avatarColor(l),
                              child: Text(
                                _initials(l),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  if (l.company?.isNotEmpty == true)
                                    Text(l.company!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                  Text(l.phone, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                              ),
                            ),
                            Icon(l.synced == 1 ? Icons.cloud_done : Icons.cloud_off,
                                color: l.synced == 1 ? Colors.green : Colors.grey),
                          ],
                        ),
                      ),
                    ),
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
