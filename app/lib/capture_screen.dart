import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';
import 'lead.dart';
import 'photos.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.lead});
  final Lead? lead;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in _fields) k: TextEditingController()};
  static const _fields = ['phone', 'name', 'company', 'email', 'website', 'city', 'state', 'products', 'note'];
  late final String _id;
  String? _frontPath, _backPath;
  bool _saving = false;
  String? _phoneError;

  static const _fieldIcons = {
    'phone': Icons.phone,
    'name': Icons.person,
    'company': Icons.business,
    'email': Icons.email,
    'website': Icons.language,
    'city': Icons.location_city,
    'state': Icons.map,
    'products': Icons.inventory_2,
    'note': Icons.notes,
  };

  static const _fieldIconColors = {
    'phone': Color(0xFF4CAF50),
    'name': Color(0xFF2196F3),
    'company': Color(0xFFFF9800),
    'email': Color(0xFFE91E63),
    'website': Color(0xFF9C27B0),
    'city': Color(0xFF00BCD4),
    'state': Color(0xFF009688),
    'products': Color(0xFFFF5722),
    'note': Color(0xFF795548),
  };

  @override
  void initState() {
    super.initState();
    final l = widget.lead;
    _id = l?.id ?? const Uuid().v4();
    if (l != null) {
      _c['phone']!.text = l.phone;
      _c['name']!.text = l.name ?? '';
      _c['company']!.text = l.company ?? '';
      _c['email']!.text = l.email ?? '';
      _c['website']!.text = l.website ?? '';
      _c['city']!.text = l.city ?? '';
      _c['state']!.text = l.state ?? '';
      _c['products']!.text = l.products ?? '';
      _c['note']!.text = l.note ?? '';
      _frontPath = l.frontPath;
      _backPath = l.backPath;
    }
    for (final c in _c.values) { c.addListener(() => setState(() {})); }
  }

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  Future<void> _shoot(String side) async {
    final path = await capturePhoto(_id, side);
    if (path != null) setState(() => side == 'front' ? _frontPath = path : _backPath = path);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final phone = _c['phone']!.text.trim();
    final isNew = widget.lead == null;
    if (isNew && await LeadDb.instance.phoneExists(phone) && mounted) {
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
      createdAt: widget.lead?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
    );
    if (isNew) {
      await LeadDb.instance.insert(lead);
    } else {
      await LeadDb.instance.update(lead);
    }
    if (mounted) Navigator.pop(context, true);
  }

  String? _t(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  bool get _hasAnyInput =>
      _fields.any((k) => _c[k]!.text.trim().isNotEmpty) ||
      _frontPath != null ||
      _backPath != null;

  bool get _phoneValid {
    final phone = _c['phone']!.text.trim();
    return phone.isEmpty || phone.length == 10;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.lead == null ? 'New lead' : 'Edit lead')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) {
                    final phone = _c['phone']!.text.trim();
                    if (phone.isNotEmpty && phone.length < 10) {
                      setState(() => _phoneError = 'Please enter 10 digits');
                    }
                  }
                },
                child: TextFormField(
                  controller: _c['phone'],
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone, color: _fieldIconColors['phone']),
                    prefixText: '+91 ',
                    errorText: _phoneError,
                  ),
                  onChanged: (v) {
                    if (v.length > 10) {
                      _c['phone']!.text = v.substring(0, 10);
                      _c['phone']!.selection = const TextSelection.collapsed(offset: 10);
                      setState(() => _phoneError = 'Phone number must be 10 digits');
                    } else {
                      setState(() => _phoneError = null);
                    }
                  },
                ),
              ),
              for (final k in _fields.where((k) => k != 'phone'))
                TextFormField(
                  controller: _c[k],
                  decoration: InputDecoration(
                    labelText: k[0].toUpperCase() + k.substring(1),
                    prefixIcon: Icon(_fieldIcons[k], color: _fieldIconColors[k]),
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _shoot('front'), icon: const Icon(Icons.camera_alt), label: Text(_frontPath == null ? 'Front photo' : 'Front ✓'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => _shoot('back'), icon: const Icon(Icons.camera_alt), label: Text(_backPath == null ? 'Back photo' : 'Back ✓'))),
              ]),
              const SizedBox(height: 16),
              FilledButton(onPressed: (_saving || !_hasAnyInput || !_phoneValid) ? null : _save, child: Text(_saving ? 'Saving…' : 'Save lead')),
              if (widget.lead != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete lead'),
                        content: const Text('This will permanently delete this lead. Continue?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      await LeadDb.instance.delete(widget.lead!.id);
                      navigator.pop(true);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete lead', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                ),
              ]
            ],
          ),
        ),
      );
}
