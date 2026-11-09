import 'package:flutter/material.dart';

/// Loader con logo della farmacia (usato in prenotazione e accesso).
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key, required this.text, this.barrierColor = Colors.black45});
  final String text;
  final Color barrierColor;
  @override
  Widget build(BuildContext context) => AbsorbPointer(
        child: Material(
          color: barrierColor,
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(alignment: Alignment.center, children: [
                  const SizedBox(width: 92, height: 92, child: CircularProgressIndicator(strokeWidth: 4, color: Color(0xFF32448C))),
                  ClipOval(child: Image.asset('assets/brand/logo_profile_200.jpg', width: 70, height: 70, fit: BoxFit.cover)),
                ]),
                const SizedBox(height: 16),
                Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF32448C))),
              ]),
            ),
          ),
        ),
      );
}
