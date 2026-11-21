import 'package:flutter/material.dart';

/// Palette eventi Google Calendar (colorId 1–11) e hex usati nell'app.
/// Google non accetta hex custom sugli eventi: solo questi ID.
class ServiceColorOption {
  final String gcalColorId;
  final String name;
  final String hex; // #RRGGBB
  const ServiceColorOption(this.gcalColorId, this.name, this.hex);

  Color get color => Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// Colori ufficiali (approssimazione UI Google Calendar).
const serviceColorPalette = <ServiceColorOption>[
  ServiceColorOption('1', 'Lavanda', '#A4BDFC'),
  ServiceColorOption('2', 'Salvia', '#7AE7BF'),
  ServiceColorOption('3', 'Uva', '#DBADFF'),
  ServiceColorOption('4', 'Fenicottero', '#FF887C'),
  ServiceColorOption('5', 'Banana', '#FBD75B'),
  ServiceColorOption('6', 'Mandarino', '#FFB878'),
  ServiceColorOption('7', 'Pavone', '#46D6DB'),
  ServiceColorOption('8', 'Grafite', '#E1E1E1'),
  ServiceColorOption('9', 'Mirtillo', '#5484ED'),
  ServiceColorOption('10', 'Basilico', '#51B749'),
  ServiceColorOption('11', 'Pomodoro', '#DC2127'),
];

const kDefaultServiceGcalColorId = '9'; // Mirtillo — vicino al navy del brand

ServiceColorOption serviceColorByGcalId(String? id) {
  final want = (id ?? '').trim();
  for (final c in serviceColorPalette) {
    if (c.gcalColorId == want) return c;
  }
  return serviceColorPalette.firstWhere((c) => c.gcalColorId == kDefaultServiceGcalColorId);
}

ServiceColorOption serviceColorByHex(String? hex) {
  final h = normalizeServiceHex(hex);
  if (h != null) {
    for (final c in serviceColorPalette) {
      if (c.hex == h) return c;
    }
  }
  return serviceColorByGcalId(kDefaultServiceGcalColorId);
}

/// Default stabile per servizi seed / senza colore salvato (allineato a `gcal.mjs`).
ServiceColorOption defaultServiceColorFor({String? id, int ordine = 0}) {
  final n = serviceColorPalette.length;
  if (ordine > 0) return serviceColorPalette[(ordine - 1) % n];
  var h = 0;
  for (final u in (id ?? '').codeUnits) {
    h = (h + u) % n;
  }
  return serviceColorPalette[h];
}

String? normalizeServiceHex(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().toUpperCase();
  if (s.isEmpty) return null;
  if (!s.startsWith('#')) s = '#$s';
  if (s.length == 4) {
    s = '#${s[1]}${s[1]}${s[2]}${s[2]}${s[3]}${s[3]}';
  }
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(s)) return null;
  return s;
}

Color colorFromServiceHex(String? hex, {Color fallback = const Color(0xFF5484ED)}) {
  final h = normalizeServiceHex(hex);
  if (h == null) return fallback;
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}

/// Testo bianco o scuro a seconda della luminosità dello sfondo.
Color contrastOn(Color bg) =>
    bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
