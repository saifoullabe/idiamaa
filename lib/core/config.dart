/// Coordonnées du projet Supabase d'IDIAMA Agro.
///
/// Ces deux valeurs se trouvent dans Supabase →
/// Project Settings → API : « Project URL » et « anon public ».
class Config {
  static const String supabaseUrl = 'https://REMPLACER.supabase.co';
  static const String supabaseAnonKey = 'REMPLACER_PAR_LA_CLE_ANON';

  /// Les gens se connectent avec un identifiant (« admin », « fermier1 »),
  /// pas avec une adresse e-mail. On lui colle ce domaine interne.
  static const String domaineInterne = 'idiamaa.com';

  static String emailDe(String login) =>
      '${login.trim().toLowerCase()}@$domaineInterne';

  static bool get estConfigure =>
      !supabaseUrl.contains('REMPLACER') && !supabaseAnonKey.contains('REMPLACER');
}
