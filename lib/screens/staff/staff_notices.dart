import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../app.dart';
import '../../models/notice.dart';
import '../../models/service_type.dart';
import '../../services/notice_service.dart';
import '../../theme/brand.dart';
import '../client/notice_image.dart';

/// Bacheca novità, eventi e promo. Scrittura riservata all'admin dalle regole Firestore.
class StaffNotices extends StatelessWidget {
  const StaffNotices({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(subtitle: 'Bacheca'),
      body: Column(children: [
        Material(
          color: Brand.primary,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.primary, minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticeEditor())),
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi novità / promo / evento', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ),
        ),
        Expanded(child: StreamBuilder<List<Notice>>(
        stream: noticeBoard.watchAll(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Bacheca non disponibile: ${snap.error}', textAlign: TextAlign.center)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nessuna novità, evento o promo.\nAggiungi la prima voce.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18))));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            for (final n in list)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: n.imageUrl.isEmpty
                      ? CircleAvatar(backgroundColor: Brand.primary.withValues(alpha: 0.1), child: Icon(_icon(n.tipo), color: Brand.primary))
                      : ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: NoticeImage(n.imageUrl))),
                  title: Text(n.titolo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  subtitle: Text('${n.tipoLabel}${n.attivo ? '' : ' · non in bacheca'} · ordine ${n.ordine}'),
                  trailing: const Icon(Icons.edit, color: Brand.primary),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeEditor(notice: n))),
                ),
              ),
          ]);
        },
      )),
      ]),
    );
  }
}

IconData _icon(String tipo) => switch (tipo) {
      'evento' => Icons.event,
      'promo' => Icons.local_offer,
      _ => Icons.campaign,
    };

class NoticeEditor extends StatefulWidget {
  final Notice? notice;
  const NoticeEditor({super.key, this.notice, this.initialTipo});
  final String? initialTipo;
  @override
  State<NoticeEditor> createState() => _NoticeEditorState();
}

class _NoticeEditorState extends State<NoticeEditor> {
  late final _titolo = TextEditingController(text: widget.notice?.titolo ?? '');
  late final _testo = TextEditingController(text: widget.notice?.testo ?? '');
  late final _url = TextEditingController(text: widget.notice != null && widget.notice!.imageUrl.startsWith('http') ? widget.notice!.imageUrl : '');
  late String _tipo = widget.notice?.tipo ?? widget.initialTipo ?? 'novita';
  late String _periodo = const {'', 'settimana', 'mese'}.contains(widget.notice?.periodo) ? widget.notice!.periodo : '';
  late bool _attivo = widget.notice?.attivo ?? true;
  late int _ordine = widget.notice?.ordine ?? 0;
  late DateTime? _start = widget.notice?.start;
  late DateTime? _end = widget.notice?.end;
  late String _image = widget.notice?.imageUrl ?? '';
  late String _serviceId = widget.notice?.serviceId ?? '';
  late String _serviceName = widget.notice?.serviceName ?? '';
  bool _busy = false;

  Future<void> _pickDate(bool start) async {
    final initial = (start ? _start : _end) ?? DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2024), lastDate: DateTime(2035));
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _periodo = '';
    });
  }

  void _applyPeriod(String periodo) {
    final now = DateTime.now();
    setState(() {
      _periodo = periodo;
      if (periodo == 'settimana') {
        final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        _start = monday;
        _end = monday.add(const Duration(days: 6));
      } else if (periodo == 'mese') {
        _start = DateTime(now.year, now.month, 1);
        _end = DateTime(now.year, now.month + 1, 0);
      }
    });
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 55);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 280000) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Immagine troppo grande. Scegline una più leggera.')));
      return;
    }
    setState(() {
      _image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _url.clear();
    });
  }

  Future<void> _save() async {
    final titolo = _titolo.text.trim();
    if (titolo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scrivi un titolo')));
      return;
    }
    final url = _url.text.trim();
    final image = url.startsWith('http') ? url : _image;
    setState(() => _busy = true);
    try {
      await noticeBoard.save(Notice(
        id: widget.notice?.id ?? '',
        titolo: titolo,
        testo: _testo.text.trim(),
        tipo: _tipo,
        imageUrl: image,
        periodo: _periodo,
        start: _start,
        end: _end,
        attivo: _attivo,
        ordine: _ordine,
        serviceId: _tipo == 'evento' ? _serviceId : '',
        serviceName: _tipo == 'evento' ? _serviceName : '',
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Salvataggio non riuscito: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final id = widget.notice?.id;
    if (id == null || id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await noticeBoard.remove(id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminazione non riuscita: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmt(DateTime? d) => d == null ? 'Nessuna' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandAppBar(subtitle: widget.notice == null ? 'Nuova voce' : 'Modifica voce'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _titolo, decoration: const InputDecoration(labelText: 'Titolo *'), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            TextField(controller: _testo, maxLines: 4, decoration: const InputDecoration(labelText: 'Testo')),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Tipo'),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _tipo,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'novita', child: Text('Novità')),
                  DropdownMenuItem(value: 'evento', child: Text('Evento')),
                  DropdownMenuItem(value: 'promo', child: Text('Promo')),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? 'novita'),
              )),
            ),
            if (_tipo == 'evento') ...[
              const SizedBox(height: 8),
              StreamBuilder<List<ServiceType>>(
                stream: bookingService.watchServices(),
                builder: (context, snap) {
                  final services = (snap.data ?? const <ServiceType>[]).where((s) => s.attivo).toList();
                  final ids = services.map((s) => s.id).toSet();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Prenotabile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      subtitle: const Text('Il cliente vede il bottone «Prenota» sulla card'),
                      value: _serviceId.isNotEmpty,
                      activeThumbColor: Brand.green,
                      onChanged: services.isEmpty ? null : (v) => setState(() {
                        if (v) { _serviceId = services.first.id; _serviceName = services.first.name; } else { _serviceId = ''; _serviceName = ''; }
                      }),
                    ),
                    if (_serviceId.isNotEmpty) InputDecorator(
                      decoration: const InputDecoration(labelText: 'Servizio da prenotare'),
                      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                        value: ids.contains(_serviceId) ? _serviceId : null,
                        hint: Text(_serviceName.isEmpty ? 'Scegli un servizio' : '$_serviceName (non attivo)'),
                        isExpanded: true,
                        items: [for (final s in services) DropdownMenuItem(value: s.id, child: Text(s.name))],
                        onChanged: (v) => setState(() { final s = services.firstWhere((x) => x.id == v); _serviceId = s.id; _serviceName = s.name; }),
                      )),
                    ),
                  ]);
                },
              ),
            ],
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Periodo'),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _periodo,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '', child: Text('Date libere o nessuna')),
                  DropdownMenuItem(value: 'settimana', child: Text('Questa settimana')),
                  DropdownMenuItem(value: 'mese', child: Text('Questo mese')),
                ],
                onChanged: (v) => _applyPeriod(v ?? ''),
              )),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(true), child: Text('Dal ${_fmt(_start)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(false), child: Text('Al ${_fmt(_end)}'))),
            ]),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() { _start = null; _end = null; _periodo = ''; }), child: const Text('Togli le date'))),
            Row(children: [
              const Text('Ordine', style: TextStyle(fontSize: 16)),
              IconButton(onPressed: _ordine > 0 ? () => setState(() => _ordine--) : null, icon: const Icon(Icons.remove)),
              Text('$_ordine', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(onPressed: () => setState(() => _ordine++), icon: const Icon(Icons.add)),
              const Spacer(),
              const Text('In bacheca'),
              Switch(value: _attivo, activeThumbColor: Brand.green, onChanged: (v) => setState(() => _attivo = v)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Indirizzo immagine (https), facoltativo'), onChanged: (v) {
              if (v.trim().startsWith('http')) setState(() => _image = v.trim());
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image), label: const Text('Carica un banner')),
            if (_image.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(height: 160, width: double.infinity, child: NoticeImage(_image))),
              TextButton(onPressed: () => setState(() { _image = ''; _url.clear(); }), child: const Text('Rimuovi immagine')),
            ],
            const SizedBox(height: 16),
            SizedBox(height: 52, child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Salvo…' : 'Salva', style: const TextStyle(fontSize: 18)))),
            if (widget.notice != null) TextButton(onPressed: _busy ? null : _delete, child: const Text('Elimina', style: TextStyle(color: Colors.red))),
          ]),
        ),
      ]),
    );
  }
}
