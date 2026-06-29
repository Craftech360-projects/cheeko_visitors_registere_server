import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'db.dart';
import 'lead.dart';
import 'lead_detail_screen.dart';
import 'sync.dart';

// ── Design tokens
const _bg = Color(0xFFFAF7F2);
const _surface = Color(0xFFFFFFFF);
const _border = Color(0xFFECE5DB);
const _ink = Color(0xFF1C1C1C);
const _ink2 = Color(0xFF5C6166);
const _ink3 = Color(0xFF9AA0A6);
const _accent = Color(0xFFE96B2C);
const _accentInk = Color(0xFFCF5A1F);
const _accentTint = Color(0xFFFFE8DA);

Color _tagColor(String? tag) => switch (tag) {
      'hot'  => const Color(0xFFC2410C),
      'warm' => const Color(0xFF9A6410),
      'cold' => const Color(0xFF3F7A1E),
      _      => _accent,
    };

// Avatar helpers (matches Leads tab)
const _palette = [
  Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784),
  Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DB6AC),
  Color(0xFFF06292), Color(0xFF90A4AE),
];

String _initials(Lead l) {
  final name = l.name?.isNotEmpty == true ? l.name! : l.phone;
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

Color _avatarColor(Lead l) {
  final name = l.name?.isNotEmpty == true ? l.name! : l.phone;
  if (name.isEmpty) return _palette[0];
  return _palette[name.codeUnitAt(0) % _palette.length];
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Lead> _leads = [];
  String _searchQuery = '';
  String _filterTag = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('${Config.serverUrl}/api/leads'));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        _leads = list.map((m) => Lead.fromMap(Map<String, Object?>.from(m as Map))).toList();
        if (mounted) setState(() {});
        return;
      }
    } catch (_) {}
    // fallback to local DB if server unreachable
    _leads = await LeadDb.instance.all();
    if (mounted) setState(() {});
  }

  List<Lead> get _filtered {
    final q = _searchQuery.toLowerCase();
    return _leads.where((l) {
      final matchesTag = _filterTag.isEmpty || l.tag == _filterTag;
      final matchesSearch = q.isEmpty ||
          (l.name ?? '').toLowerCase().contains(q) ||
          (l.company ?? '').toLowerCase().contains(q) ||
          l.phone.toLowerCase().contains(q);
      return matchesTag && matchesSearch;
    }).toList();
  }

  Future<void> _enrichAll(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: _surface,
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Syncing & enriching leads…')),
        ]),
      ),
    );
    try {
      await syncAll();
      final res = await http.post(Uri.parse('${Config.serverUrl}/api/enrich-all'));
      if (!context.mounted) return;
      Navigator.pop(context);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final enriched = data['enriched'] as int;
        final total = data['total'] as int;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('✨ Done', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            content: Text(
              total == 0
                  ? 'No pending leads to enrich.\nSync leads with card photos first.'
                  : '$enriched of $total lead${total == 1 ? '' : 's'} enriched.',
              style: const TextStyle(color: _ink2, fontSize: 13),
            ),
            actions: [TextButton(
              onPressed: () { Navigator.pop(ctx); _load(); },
              child: Text('OK', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
            )],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Failed', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            content: Text('Server error ${res.statusCode}', style: const TextStyle(color: _ink2, fontSize: 13)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)))],
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrich failed. Check your connection.')),
        );
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Download file?', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        content: const Text('leads_export.csv\nSource: 157.245.108.139:8080',
            style: TextStyle(color: _ink2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Download', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading…'), duration: Duration(seconds: 60)),
    );

    try {
      final response = await http.get(Uri.parse('http://157.245.108.139:8080/export.csv'));
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) await dir.create(recursive: true);
      await File('${dir.path}/leads_export.csv').writeAsBytes(response.bodyBytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final filePath = '${dir.path}/leads_export.csv';
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Downloaded!', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            content: const Text('leads_export.csv saved to Downloads.\nOpen it now?',
                style: TextStyle(color: _ink2, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () { Navigator.pop(ctx); OpenFile.open(filePath); },
                child: Text('Open file', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Check connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total   = _leads.length;
    final hot     = _leads.where((l) => l.tag == 'hot').length;
    final warm    = _leads.where((l) => l.tag == 'warm').length;
    final cold    = _leads.where((l) => l.tag == 'cold').length;
    final synced  = _leads.where((l) => l.synced == 1).length;
    final pending = _leads.where((l) => l.synced == 0).length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Leads Dashboard',
            style: TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            const _Banner(),
            const SizedBox(height: 14),
            _sectionLabel('Overview'),
            const SizedBox(height: 8),
            Row(children: [
              _MetricCard(label: 'Total',    value: total,   valueColor: _accent),
              _MetricCard(label: 'Synced ✓', value: synced,  valueColor: const Color(0xFF3F7A1E)),
              _MetricCard(label: 'Pending',  value: pending, valueColor: _accentInk),
            ]),
            const SizedBox(height: 14),
            _sectionLabel('Priority'),
            const SizedBox(height: 8),
            Row(children: [
              _MetricCard(label: 'Hot 🔴',  value: hot,  valueColor: const Color(0xFFC2410C)),
              _MetricCard(label: 'Warm 🟡', value: warm, valueColor: const Color(0xFF9A6410)),
              _MetricCard(label: 'Cold 🟢', value: cold, valueColor: const Color(0xFF3F7A1E)),
            ]),
            const SizedBox(height: 20),
            _ToolsBar(
              controller: _searchCtrl,
              filterTag: _filterTag,
              onSearch: (q) => setState(() => _searchQuery = q),
              onFilter: (t) => setState(() => _filterTag = t),
              onExport: () => _exportCsv(context),
              onEnrich: () => _enrichAll(context),
            ),
            const SizedBox(height: 12),
            _sectionLabel('${_filtered.length} Lead${_filtered.length == 1 ? '' : 's'}'),
            const SizedBox(height: 8),
            _LeadsList(leads: _filtered),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _ink3, letterSpacing: 0.8),
      );
}

// ── Banner
class _Banner extends StatelessWidget {
  const _Banner();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.white, _accentTint],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(children: [
              Container(
                width: 5,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF8A3D), _accent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('🎯 Captured Leads',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
                      SizedBox(height: 3),
                      Text('Leads collected at the stall',
                          style: TextStyle(fontSize: 12, color: _ink2)),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ── Metric card — Style A: white card + colored left accent strip
class _MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final Color valueColor;
  const _MetricCard({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: IntrinsicHeight(
                child: Row(children: [
                  Container(width: 4, color: valueColor.withValues(alpha: 0.35)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                      child: Column(children: [
                        Text('$value',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: valueColor, height: 1.1)),
                        const SizedBox(height: 4),
                        Text(label.toUpperCase(),
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: _ink3, letterSpacing: 0.4),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

// ── Tools bar
class _ToolsBar extends StatelessWidget {
  final TextEditingController controller;
  final String filterTag;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFilter;
  final VoidCallback onExport;
  final VoidCallback onEnrich;
  const _ToolsBar({required this.controller, required this.filterTag, required this.onSearch, required this.onFilter, required this.onExport, required this.onEnrich});

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: _surface, border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(13),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
              ),
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                style: const TextStyle(fontSize: 14, color: _ink),
                decoration: const InputDecoration(
                  hintText: 'Search name / company / phone…',
                  hintStyle: TextStyle(fontSize: 13, color: _ink3),
                  prefixIcon: Icon(Icons.search, size: 18, color: _ink3),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _surface, border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: filterTag,
                style: const TextStyle(fontSize: 13, color: _ink, fontWeight: FontWeight.w700),
                icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _ink3),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'hot', child: Text('🔴 Hot')),
                  DropdownMenuItem(value: 'warm', child: Text('🟡 Warm')),
                  DropdownMenuItem(value: 'cold', child: Text('🟢 Cold')),
                ],
                onChanged: (v) => onFilter(v ?? ''),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: onExport,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(9999),
                  boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.download, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('Export CSV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onEnrich,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF5F3DC4),
                  borderRadius: BorderRadius.circular(9999),
                  boxShadow: [BoxShadow(color: const Color(0xFF5F3DC4).withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('✨', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 6),
                  Text('Enrich all pending',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ]),
      ]);
}

// ── Leads list — individual floating cards
class _LeadsList extends StatelessWidget {
  final List<Lead> leads;
  const _LeadsList({required this.leads});

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No leads yet.\nGo to Leads tab to add one.',
              textAlign: TextAlign.center, style: TextStyle(color: _ink3, fontSize: 14)),
        ),
      );
    }
    return Column(
      children: leads
          .map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LeadRow(lead: l),
              ))
          .toList(),
    );
  }
}

// ── Lead row — individual card with colored left bar + initials avatar
class _LeadRow extends StatelessWidget {
  final Lead lead;
  const _LeadRow({required this.lead});

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    await launchUrl(Uri.parse('https://wa.me/91$cleaned'), mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    await launchUrl(Uri.parse('tel:+91$cleaned'), mode: LaunchMode.externalApplication);
  }

  Future<void> _enrichLead(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: _surface,
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Enriching lead…')),
        ]),
      ),
    );
    try {
      final res = await http.post(Uri.parse('${Config.serverUrl}/api/leads/${lead.id}/enrich'));
      if (!context.mounted) return;
      Navigator.pop(context);
      if (res.statusCode == 200) {
        final filled = (jsonDecode(res.body)['filled'] as List?)?.cast<String>() ?? [];
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('✨ Enriched!', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            content: Text(
              filled.isEmpty ? 'No new fields to fill.' : 'Filled: ${filled.join(', ')}',
              style: const TextStyle(color: _ink2, fontSize: 13),
            ),
            actions: [TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
            )],
          ),
        );
      } else {
        final err = (jsonDecode(res.body)['error'] ?? 'unknown') as String;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Enrich failed', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            content: Text(
              err == 'no_photo' ? 'No photo on server. Sync this lead with a card photo first.' : 'Error: $err',
              style: const TextStyle(color: _ink2, fontSize: 13),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)))],
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrich failed. Check your connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final displayName = l.name?.isNotEmpty == true ? l.name! : l.phone;
    final barColor = _tagColor(l.tag);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored left bar
              Container(width: 5, color: barColor.withValues(alpha: 0.5)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Colorful initials avatar
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _avatarColor(l),
                        child: Text(
                          _initials(l),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink, letterSpacing: -0.2)),
                              ),
                              if (l.tag != null) ...[const SizedBox(width: 6), _TagBadge(l.tag!)],
                            ]),
                            if (l.company?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(l.company!, style: const TextStyle(fontSize: 12, color: _ink2)),
                            ],
                            const SizedBox(height: 2),
                            Text(l.phone, style: const TextStyle(fontSize: 12, color: _ink3)),
                            if (l.city?.isNotEmpty == true || l.state?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              _LocationPill(city: l.city, state: l.state),
                            ],
                            if (l.products?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(l.products!, style: const TextStyle(fontSize: 11, color: _ink2),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 12),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              _ActionBtn(
  label: '',
  bg: const Color(0xFFE6F6DA),
  fg: const Color(0xFF3F7A1E),
  icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF3F7A1E)),
  onTap: () => _openWhatsApp(l.phone),
),
                              _ActionBtn(label: '📞', bg: const Color(0xFFF1ECE4), fg: const Color(0xFF5A5249), onTap: () => _call(l.phone)),
                              _ActionBtn(
  label: lead.enrichedAt != null ? '✨ Enriched' : '✨ Enrich',
  bg: _accentTint,
  fg: lead.enrichedAt != null ? _ink3 : _accentInk,
  onTap: lead.enrichedAt == null ? () => _enrichLead(context) : null,
),
                              _ActionBtn(
                                label: 'ⓘ Details',
                                bg: const Color(0xFFF1ECE4),
                                fg: const Color(0xFF5A5249),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeadDetailScreen(lead: l))),
                              ),
                            ]),
                          ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

// ── Action pill button
class _ActionBtn extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final VoidCallback? onTap;
  final Widget? icon;
  const _ActionBtn({required this.label, required this.bg, required this.fg, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final textColor = onTap == null ? fg.withValues(alpha: 0.5) : fg;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: onTap == null ? bg.withValues(alpha: 0.5) : bg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: icon != null
            ? label.isEmpty
                ? icon!
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    icon!,
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
                  ])
            : Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
      ),
    );
  }
}

// ── Tag badge
class _TagBadge extends StatelessWidget {
  final String tag;
  const _TagBadge(this.tag);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tag) {
      'hot'  => (const Color(0xFFFFE6E0), const Color(0xFFC2410C)),
      'warm' => (const Color(0xFFFFF3D9), const Color(0xFF9A6410)),
      'cold' => (const Color(0xFFE6F6DA), const Color(0xFF3F7A1E)),
      _      => (const Color(0xFFF1ECE4), _ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9999)),
      child: Text(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.2)),
    );
  }
}

// ── Location pill
class _LocationPill extends StatelessWidget {
  final String? city, state;
  const _LocationPill({this.city, this.state});

  @override
  Widget build(BuildContext context) {
    final parts = [if (city?.isNotEmpty == true) city!, if (state?.isNotEmpty == true) state!];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: _accentTint, borderRadius: BorderRadius.circular(9999)),
      child: Text(parts.join(', '),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _accentInk)),
    );
  }
}
