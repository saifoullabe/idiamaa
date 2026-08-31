import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Palette IDIAMA — le vert de la ferme, l'or du maïs, le rouge des alertes.
class Palette {
  static const vert = Color(0xFF1B5E20);
  static const vertMoyen = Color(0xFF2E7D32);
  static const vertClair = Color(0xFF4CAF50);
  static const or = Color(0xFFF9A825);
  static const orFonce = Color(0xFFE65100);
  static const rouge = Color(0xFFC62828);
  static const bleu = Color(0xFF0277BD);
  static const gris = Color(0xFF607D8B);
  static const beige = Color(0xFFF4F7F0);
  static const nuit = Color(0xFF0F1610);

  /// Couleur d'ambiance de chaque rôle : elle habille l'en-tête,
  /// pour qu'on sache d'un coup d'œil dans quel espace on est.
  static Color duRole(String role) => switch (role) {
        'admin' => const Color(0xFFBF360C),
        'gerant' => vert,
        _ => bleu,
      };

  static List<Color> degradeRole(String role) => switch (role) {
        'admin' => const [Color(0xFF3E1A00), Color(0xFFBF360C)],
        'gerant' => const [Color(0xFF071A07), vert],
        _ => const [Color(0xFF003060), bleu],
      };
}

class AppTheme {
  static ThemeData clair() => _construire(Brightness.light);
  static ThemeData sombre() => _construire(Brightness.dark);

  static ThemeData _construire(Brightness luminosite) {
    final sombre = luminosite == Brightness.dark;
    final schema = ColorScheme.fromSeed(
      seedColor: Palette.vert,
      brightness: luminosite,
      primary: sombre ? Palette.vertClair : Palette.vert,
      secondary: Palette.or,
      error: Palette.rouge,
      surface: sombre ? const Color(0xFF141C15) : Colors.white,
    );

    final fond = sombre ? Palette.nuit : Palette.beige;

    return ThemeData(
      useMaterial3: true,
      colorScheme: schema,
      scaffoldBackgroundColor: fond,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: sombre ? const Color(0xFF141C15) : Colors.white,
        foregroundColor: sombre ? Colors.white : Palette.vert,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        systemOverlayStyle:
            sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: sombre ? Colors.white : Palette.vert,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: schema.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: sombre ? Colors.white10 : const Color(0xFFE2EAE0),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sombre ? Colors.white10 : const Color(0xFFF7FAF6),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: _bordure(sombre ? Colors.white24 : const Color(0xFFCDD9CD)),
        enabledBorder:
            _bordure(sombre ? Colors.white24 : const Color(0xFFCDD9CD)),
        focusedBorder: _bordure(schema.primary, epaisseur: 2),
        errorBorder: _bordure(Palette.rouge),
        focusedErrorBorder: _bordure(Palette.rouge, epaisseur: 2),
        labelStyle: TextStyle(
          color: sombre ? Colors.white70 : Palette.gris,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: schema.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle:
              const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle:
              const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 3,
        backgroundColor: sombre ? const Color(0xFF141C15) : Colors.white,
        indicatorColor: schema.primary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (etats) => TextStyle(
            fontSize: 11.5,
            fontWeight: etats.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: etats.contains(WidgetState.selected)
                ? schema.primary
                : Palette.gris,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      dialogTheme: DialogThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
      ),
      dividerTheme: DividerThemeData(
        color: sombre ? Colors.white12 : const Color(0xFFE6EDE4),
        thickness: 1,
        space: 1,
      ),
      textTheme: _texte(sombre),
    );
  }

  static OutlineInputBorder _bordure(Color c, {double epaisseur = 1.5}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: c, width: epaisseur),
      );

  static TextTheme _texte(bool sombre) {
    final principal = sombre ? Colors.white : const Color(0xFF1A2E1A);
    return TextTheme(
      displaySmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: principal),
      headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: principal),
      titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: principal),
      titleMedium: TextStyle(
          fontSize: 15.5, fontWeight: FontWeight.w700, color: principal),
      titleSmall: TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w700, color: principal),
      bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: principal),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.4, color: principal),
      bodySmall: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: sombre ? Colors.white70 : Palette.gris),
      labelLarge: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: principal),
      labelMedium: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: sombre ? Colors.white70 : Palette.gris),
      labelSmall: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: sombre ? Colors.white60 : Palette.gris),
    );
  }
}
