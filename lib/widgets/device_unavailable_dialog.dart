import 'package:flutter/material.dart';
import '../models/device.dart';

/// Popup obbligatorio al salvataggio se l'apparecchio è occupato. Bottone OK.
Future<void> showDeviceUnavailableDialog(BuildContext context, DeviceUnavailableException e) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(e.message),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}
