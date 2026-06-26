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
