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
