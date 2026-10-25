import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Les polices des documents PDF.
///
/// Le paquet « pdf » utilise par défaut les polices internes du format,
/// qui ne portent que l'alphabet latin-1. Tout ce qui en sort —
/// l'apostrophe française ’, le tiret long —, les guillemets « », le
/// signe €, la coche ✓ — est dessiné EN BLANC : rien ne s'affiche, et
/// aucune erreur n'est levée. Une facture peut donc partir chez un
/// client avec des trous au milieu des phrases.
///
/// On embarque donc Roboto, la police de Flutter, et on la charge une
/// seule fois : lire 340 Ko à chaque facture ralentirait pour rien.
class Polices {
  static pw.ThemeData? _theme;

  /// Le thème à passer à chaque document. Chargé une fois, gardé ensuite.
  static Future<pw.ThemeData> theme() async {
    if (_theme != null) return _theme!;
    final normale =
        pw.Font.ttf(await rootBundle.load('assets/polices/roboto-regular.ttf'));
    final grasse =
        pw.Font.ttf(await rootBundle.load('assets/polices/roboto-bold.ttf'));
    _theme = pw.ThemeData.withFont(
      base: normale,
      bold: grasse,
      italic: normale,
      boldItalic: grasse,
    );
    return _theme!;
  }
}
