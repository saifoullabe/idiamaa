import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'data/etat.dart';
import 'screens/coquille.dart';
import 'screens/connexion.dart';
import 'screens/reglage_manquant.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  if (Config.estConfigure) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      anonKey: Config.supabaseAnonKey,
    );
  }

  final prefs = await SharedPreferences.getInstance();
  runApp(IdiamaApp(prefs: prefs));
}

class IdiamaApp extends StatefulWidget {
  final SharedPreferences prefs;
  const IdiamaApp({super.key, required this.prefs});

  @override
  State<IdiamaApp> createState() => _IdiamaAppState();
}

class _IdiamaAppState extends State<IdiamaApp> {
  late ThemeMode _mode = switch (widget.prefs.getString('theme')) {
    'clair' => ThemeMode.light,
    'sombre' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void _changerTheme(ThemeMode m) {
    setState(() => _mode = m);
    widget.prefs.setString(
        'theme',
        switch (m) {
          ThemeMode.light => 'clair',
          ThemeMode.dark => 'sombre',
          ThemeMode.system => 'systeme',
        });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Etat()..reprendreSession(),
      child: PreferencesTheme(
        mode: _mode,
        changer: _changerTheme,
        child: MaterialApp(
          title: 'IDIAMA Agro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.clair(),
          darkTheme: AppTheme.sombre(),
          themeMode: _mode,
          locale: const Locale('fr', 'FR'),
          supportedLocales: const [Locale('fr', 'FR'), Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, enfant) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.3,
            child: enfant!,
          ),
          home: Config.estConfigure ? const Portail() : const ReglageManquant(),
        ),
      ),
    );
  }
}

/// Donne accès au réglage clair/sombre depuis n'importe quel écran.
class PreferencesTheme extends InheritedWidget {
  final ThemeMode mode;
  final void Function(ThemeMode) changer;

  const PreferencesTheme({
    super.key,
    required this.mode,
    required this.changer,
    required super.child,
  });

  static PreferencesTheme of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PreferencesTheme>()!;

  @override
  bool updateShouldNotify(PreferencesTheme ancien) => ancien.mode != mode;
}

/// Aiguillage : écran de connexion, ou l'application selon le rôle.
class Portail extends StatelessWidget {
  const Portail({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: etat.connecte
          ? const Coquille(key: ValueKey('app'))
          : const EcranConnexion(key: ValueKey('connexion')),
    );
  }
}
