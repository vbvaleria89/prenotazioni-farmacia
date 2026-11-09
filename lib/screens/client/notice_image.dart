import 'dart:convert';

import 'package:flutter/material.dart';

/// Banner di una voce: indirizzo https oppure data URL (come le foto ricetta, senza Storage).
class NoticeImage extends StatelessWidget {
  final String source;
  const NoticeImage(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    if (source.startsWith('data:image')) {
      final comma = source.indexOf(',');
      if (comma < 0) return const SizedBox.shrink();
      try {
        final bytes = base64Decode(source.substring(comma + 1));
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    if (source.startsWith('http')) {
      return Image.network(source, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink());
    }
    return const SizedBox.shrink();
  }
}
