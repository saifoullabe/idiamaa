/// Coordonnées du projet Supabase d'IDIAMA Agro.
///
/// Ces deux valeurs se trouvent dans Supabase →
/// Project Settings → API : « Project URL » et « anon public ».
class Config {
  static const String supabaseUrl = 'https://necshjtfplwwdaqdxrzl.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5lY3NoanRmcGx3d2RhcWR4cnpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyMTI5ODYsImV4cCI6MjEwMzc4ODk4Nn0.SaC0sdJDmnXZgnH6UHMNenUpUnLOQ-LvQaPdlWxpIjE';

  /// Les gens se connectent avec un identifiant (« admin », « fermier1 »),
  /// pas avec une adresse e-mail. On lui colle ce domaine interne.
  static const String domaineInterne = 'idiamaa.com';

  static String emailDe(String login) =>
      '${login.trim().toLowerCase()}@$domaineInterne';

  static bool get estConfigure =>
      !supabaseUrl.contains('REMPLACER') && !supabaseAnonKey.contains('REMPLACER');
}
