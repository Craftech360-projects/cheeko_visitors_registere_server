import 'package:uuid/uuid.dart';

class Lead {
  final String id;
  final String phone;
  final String? name, company, email, website, city, state, products, note, tag;
  final String? frontPath, backPath;
  final String? audioPath; // local voice-note file (this device)
  final String? audioUrl, audioTranscript; // server-side (Storage URL + Gemini transcript)
  final String createdAt;
  final String? enrichedAt;
  final int synced;

  Lead({
    required this.id, required this.phone, this.name, this.company, this.email,
    this.website, this.city, this.state, this.products, this.note, this.tag,
    this.frontPath, this.backPath, this.audioPath, this.audioUrl, this.audioTranscript,
    required this.createdAt, this.enrichedAt, this.synced = 0,
  });

  factory Lead.create({
    required String phone, String? name, String? company, String? email,
    String? website, String? city, String? state, String? products, String? note,
    String? tag, String? frontPath, String? backPath, String? audioPath,
  }) =>
      Lead(
        id: const Uuid().v4(), phone: phone, name: name, company: company,
        email: email, website: website, city: city, state: state, products: products,
        note: note, tag: tag, frontPath: frontPath, backPath: backPath, audioPath: audioPath,
        createdAt: DateTime.now().toUtc().toIso8601String(), synced: 0,
      );

  Lead copyWith({
    String? phone, String? name, String? company, String? email, String? website,
    String? city, String? state, String? products, String? note, String? tag,
    String? frontPath, String? backPath, String? audioPath, int? synced,
  }) =>
      Lead(
        id: id, phone: phone ?? this.phone, name: name ?? this.name,
        company: company ?? this.company, email: email ?? this.email,
        website: website ?? this.website, city: city ?? this.city,
        state: state ?? this.state, products: products ?? this.products,
        note: note ?? this.note, tag: tag ?? this.tag,
        frontPath: frontPath ?? this.frontPath, backPath: backPath ?? this.backPath,
        audioPath: audioPath ?? this.audioPath,
        audioUrl: audioUrl, audioTranscript: audioTranscript,
        createdAt: createdAt, enrichedAt: enrichedAt, synced: synced ?? this.synced,
      );

  Map<String, Object?> toMap() => {
        'id': id, 'phone': phone, 'name': name, 'company': company, 'email': email,
        'website': website, 'city': city, 'state': state, 'products': products,
        'note': note, 'tag': tag, 'front_path': frontPath, 'back_path': backPath,
        'audio_path': audioPath,
        'created_at': createdAt, 'synced': synced,
      };

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
        id: m['id'] as String, phone: (m['phone'] as String?) ?? '', name: m['name'] as String?,
        company: m['company'] as String?, email: m['email'] as String?,
        website: m['website'] as String?, city: m['city'] as String?,
        state: m['state'] as String?, products: m['products'] as String?,
        note: m['note'] as String?, tag: m['tag'] as String?,
        frontPath: m['front_path'] as String?, backPath: m['back_path'] as String?,
        audioPath: m['audio_path'] as String?,
        audioUrl: m['audio_url'] as String?, // present only on server rows
        audioTranscript: m['audio_transcript'] as String?,
        createdAt: m['created_at'] as String,
        enrichedAt: m['enriched_at'] as String?,
        synced: (m['synced'] as int?) ?? 0,
      );
}
