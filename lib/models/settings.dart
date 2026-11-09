import 'package:cloud_firestore/cloud_firestore.dart';

import 'whatsapp.dart';

/// Documento `settings/pharmacy` (modificabile dal backoffice admin).
class PharmacySettings {
  final int openHour, closeHour;
  final Set<int> tricologicoDays; // 1=lun ... 7=dom
  final String tricologoEmployeeId, tricologoNome, serviziNote, whatsapp;
  /// Template messaggio cliente → farmacia; usa `[Nome]` per il nome del cliente.
  final String whatsappClientMessage;
  const PharmacySettings({
    this.openHour = 9,
    this.closeHour = 19,
    this.tricologicoDays = const {2, 4},
    this.tricologoEmployeeId = '',
    this.tricologoNome = 'Referente tricologico',
    this.serviziNote = '',
    this.whatsapp = '',
    this.whatsappClientMessage = kDefaultWhatsappClientMessage,
  });

  factory PharmacySettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PharmacySettings();
    final rawMsg = (m['whatsappClientMessage'] ?? '').toString().trim();
    return PharmacySettings(
      openHour: (m['openHour'] ?? 9) as int,
      closeHour: (m['closeHour'] ?? 19) as int,
      tricologicoDays: {for (final d in (m['tricologicoDays'] as List? ?? [2, 4])) d as int},
      tricologoEmployeeId: (m['tricologoEmployeeId'] ?? '') as String,
      tricologoNome: (m['tricologoNome'] ?? '') as String,
      serviziNote: (m['serviziNote'] ?? '') as String,
      whatsapp: (m['whatsapp'] ?? '') as String,
      whatsappClientMessage: rawMsg.isEmpty ? kDefaultWhatsappClientMessage : rawMsg,
    );
  }

  Map<String, dynamic> toMap() => {
        'openHour': openHour,
        'closeHour': closeHour,
        'tricologicoDays': tricologicoDays.toList()..sort(),
        'tricologoEmployeeId': tricologoEmployeeId,
        'tricologoNome': tricologoNome,
        'serviziNote': serviziNote,
        'whatsapp': whatsapp,
        'whatsappClientMessage': whatsappClientMessage.trim().isEmpty
            ? kDefaultWhatsappClientMessage
            : whatsappClientMessage.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// Documento `employees/{uid}` (uid = Firebase Auth uid).
class Employee {
  final String id, email, nome, ruolo; // ruolo: admin | staff | tricologo
  final bool attivo;
  const Employee({required this.id, required this.email, required this.nome, required this.ruolo, required this.attivo});
  bool get isAdmin => ruolo == 'admin';
  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final raw = d.data();
    final m = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
    final at = m['attivo'];
    return Employee(
        id: d.id,
        email: (m['email'] ?? '').toString(),
        nome: (m['nome'] ?? '').toString(),
        ruolo: (m['ruolo'] ?? 'staff').toString().trim().toLowerCase(),
        attivo: at is bool ? at : true);
  }
}
