import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'lead.dart';

// ── Design tokens (mirrors style.css)
const _bg = Color(0xFFFAF7F2);
const _surface = Color(0xFFFFFFFF);
const _border = Color(0xFFECE5DB);
const _borderSoft = Color(0xFFF1ECE4);
const _ink = Color(0xFF1C1C1C);
const _ink2 = Color(0xFF5C6166);
const _ink3 = Color(0xFF9AA0A6);

class LeadDetailScreen extends StatelessWidget {
  final Lead lead;
  const LeadDetailScreen({super.key, required this.lead});

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final displayName = l.name?.isNotEmpty == true ? l.name! : l.phone;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(displayName,
            style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (l.tag != null) ...[
              _PriorityBanner(tag: l.tag!),
              const SizedBox(height: 14),
            ],
            _sectionLabel('Details'),
            const SizedBox(height: 8),
            _Card(children: [
              _Row2('Name', l.name, 'Company', l.company),
              _Row2('Priority', l.tag, 'Phone', l.phone),
              _Row2('Email', l.email, 'Website', l.website),
              _Row2('City', l.city, 'State / Region', l.state),
              _Row1('Products / Interest', l.products),
              _Row1('Note', l.note),
              _Row1('Voice transcript', l.audioTranscript),
              _Row1('Captured', _formatDate(l.createdAt)),
            ]),
            if (l.audioPath != null || l.audioUrl != null) ...[
              const SizedBox(height: 20),
              _sectionLabel('Voice note'),
              const SizedBox(height: 8),
              _Card(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Text('🎙', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Recorded note', style: TextStyle(fontSize: 13, color: _ink))),
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline, color: _ink2),
                      tooltip: 'Play',
                      onPressed: () {
                        // Local file when it exists on this device; else stream the server copy.
                        if (l.audioPath != null && File(l.audioPath!).existsSync()) {
                          OpenFile.open(l.audioPath!);
                        } else if (l.audioUrl != null) {
                          launchUrl(Uri.parse(l.audioUrl!), mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ]),
                ),
              ]),
            ],
            if (l.frontPath != null || l.backPath != null) ...[
              const SizedBox(height: 20),
              _sectionLabel('Photos'),
              const SizedBox(height: 8),
              _Card(children: [
                if (l.frontPath != null) _PhotoRow(label: 'Front', path: l.frontPath),
                if (l.frontPath != null && l.backPath != null)
                  const Divider(height: 1, thickness: 1, color: _borderSoft),
                if (l.backPath != null) _PhotoRow(label: 'Back', path: l.backPath),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _ink3, letterSpacing: 0.8),
      );

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Priority banner
class _PriorityBanner extends StatelessWidget {
  final String tag;
  const _PriorityBanner({required this.tag});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, emoji) = switch (tag) {
      'hot'  => (const Color(0xFFFFE6E0), const Color(0xFFC2410C), '🔴'),
      'warm' => (const Color(0xFFFFF3D9), const Color(0xFF9A6410), '🟡'),
      'cold' => (const Color(0xFFE6F6DA), const Color(0xFF3F7A1E), '🟢'),
      _      => (const Color(0xFFF1ECE4), _ink2, ''),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _border),
      ),
      child: Text('$emoji  Priority: ${tag.toUpperCase()}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ── Card container (auto-inserts dividers)
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(const Divider(height: 1, thickness: 1, color: _borderSoft));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: items),
      ),
    );
  }
}

// ── 2-column field row
class _Row2 extends StatelessWidget {
  final String l1, l2;
  final String? v1, v2;
  const _Row2(this.l1, this.v1, this.l2, this.v2);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Field(label: l1, value: v1)),
            const SizedBox(width: 20),
            Expanded(child: _Field(label: l2, value: v2)),
          ],
        ),
      );
}

// ── Full-width field row
class _Row1 extends StatelessWidget {
  final String label;
  final String? value;
  const _Row1(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: _Field(label: label, value: value),
      );
}

// ── Label + value
class _Field extends StatelessWidget {
  final String label;
  final String? value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final hasValue = value?.isNotEmpty == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _ink3, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Text(hasValue ? value! : '—',
            style: TextStyle(fontSize: 13, color: hasValue ? _ink : _ink3)),
      ],
    );
  }
}

// ── Photo row
class _PhotoRow extends StatelessWidget {
  final String label;
  final String? path;
  const _PhotoRow({required this.label, required this.path});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _ink3, letterSpacing: 0.5)),
            const SizedBox(height: 10),
            if (path != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.file(
                  File(path!),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF8F4),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0xFFDDD3C6), width: 1.5),
                    ),
                    child: const Center(child: Text('🪪', style: TextStyle(fontSize: 32))),
                  ),
                ),
              )
            else
              const Text('—', style: TextStyle(fontSize: 13, color: _ink3)),
          ],
        ),
      );
}
