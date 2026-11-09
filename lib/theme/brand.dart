import 'package:flutter/material.dart';

/// Identità Farmacia San Ciro (dott.ri Guerra, Bagnoli).
class Brand {
  static const name = 'Farmacia San Ciro';
  static const tagline = 'dott.ri Guerra';
  static const motto = 'Il nostro scopo è il tuo benessere';
  static const address = 'Via Giacinto de Sivo 1, 80124 Napoli';
  static const phone = '081 570 4733';
  static const logo = 'assets/brand/logo_profile_200.jpg';
  static const primary = Color(0xFF32448C);
  static const green = Color(0xFF2E9E4F);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: green,
      onSecondary: Colors.white,
      tertiary: green,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// AppBar con logo + nome farmacia + tagline; [subtitle] = titolo della schermata.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({super.key, this.subtitle, this.actions, this.implyLeading = true});
  final bool implyLeading;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => Size.fromHeight(subtitle != null ? 72 : 64);

  @override
  Widget build(BuildContext context) {
    final height = subtitle != null ? 72.0 : 64.0;
    return AppBar(
      toolbarHeight: height,
      automaticallyImplyLeading: implyLeading,
      actions: actions,
      title: Row(children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          backgroundImage: AssetImage(Brand.logo),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: Brand.name,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: Brand.tagline,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
