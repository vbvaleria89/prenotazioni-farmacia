import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Avviso per gli admin nella home: compare solo se Google Calendar è scollegato
/// (token scaduto o revocato, oppure mai collegato). Nessun avviso se lo stato non è leggibile.
class GcalAlertBanner extends StatefulWidget {
  final VoidCallback onReconnect;
  const GcalAlertBanner({super.key, required this.onReconnect});
  @override
  State<GcalAlertBanner> createState() => _GcalAlertBannerState();
}

class _GcalAlertBannerState extends State<GcalAlertBanner> {
  String? _reason; // 'expired' | 'not_connected' | null (= tutto ok o sconosciuto)

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final r = await http.get(Uri.base.resolve('/api/gcal-status'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 || !mounted) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      setState(() => _reason = j['connected'] == true ? null : (j['reason'] as String? ?? 'not_connected'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_reason == null) return const SizedBox.shrink();
    final expired = _reason == 'expired';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.red.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Icon(Icons.event_busy, color: Colors.red.shade700, size: 30),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                expired
                    ? 'Google Calendar scollegato: il collegamento con Google è scaduto o revocato, le prenotazioni non arrivano più sul calendario. Ricollegalo con farmaciasanciro.servizi@gmail.com.'
                    : 'Google Calendar non collegato: le prenotazioni non arrivano sul calendario. Collegalo con farmaciasanciro.servizi@gmail.com.',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () { widget.onReconnect(); },
              icon: const Icon(Icons.link),
              label: Text(expired ? 'Ricollega' : 'Collega'),
            ),
          ]),
        ),
      ),
    );
  }
}
