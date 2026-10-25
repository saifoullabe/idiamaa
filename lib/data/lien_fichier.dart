import 'package:supabase_flutter/supabase_flutter.dart';

/// Levée quand la base refuse l'accès au fichier — compte suspendu, ou
/// fichier d'une autre ferme. À distinguer d'une panne de réseau : on
/// ne dit pas la même chose à la personne.
class LienRefuse implements Exception {
  const LienRefuse();
  @override
  String toString() => 'Fichier refusé';
}

/// Transforme l'adresse d'un fichier en adresse signée, valable une heure.
///
/// Le coffre était PUBLIC : l'adresse d'une photo, d'une pièce d'identité
/// ou d'un contrat suffisait à l'ouvrir, sans compte, depuis n'importe
/// où dans le monde. Le fermer casse toutes les adresses déjà
/// enregistrées en base — on ne les change donc pas : on en extrait le
/// chemin et on demande une adresse signée au moment de l'affichage.
class LienFichier {
  static const _marqueur = '/storage/v1/object/public/documents/';
  static const _coffre = 'documents';

  /// chemin -> (adresse signée, moment où elle expire)
  static final Map<String, _Signe> _cache = {};

  /// Les signatures DÉJÀ demandées et pas encore revenues. Sans cela,
  /// un écran qui monte 80 pastilles de la même personne d'un coup
  /// lançait 80 requêtes en parallèle : exactement ce qu'il ne faut pas
  /// faire sur un réseau faible.
  static final Map<String, Future<String>> _enCours = {};

  /// Le chemin dans le coffre, ou null si cette adresse n'en vient pas.
  static String? cheminDe(String adresse) {
    if (adresse.isEmpty) return null;
    // Un chemin nu (ce que l'on enregistrera désormais) se reconnaît à
    // ce qu'il ne commence pas par http.
    if (!adresse.startsWith('http')) return adresse;
    final i = adresse.indexOf(_marqueur);
    if (i < 0) return null;
    final brut = adresse.substring(i + _marqueur.length);
    // Supabase ajoute parfois « ?t=... » : le chemin s'arrête avant.
    final q = brut.indexOf('?');
    return Uri.decodeFull(q < 0 ? brut : brut.substring(0, q));
  }

  /// L'adresse à donner à Image.network. Rend l'adresse d'origine si ce
  /// n'est pas un fichier du coffre.
  ///
  /// Lève [LienRefuse] quand la base refuse, pour que l'écran puisse
  /// dire la vraie raison au lieu d'afficher une image cassée.
  static Future<String> affichable(String adresse,
      {bool forcer = false}) async {
    final chemin = cheminDe(adresse);
    if (chemin == null) return adresse;

    if (forcer) {
      _cache.remove(chemin);
    } else {
      final garde = _cache[chemin];
      if (garde != null && garde.expire.isAfter(DateTime.now())) {
        return garde.adresse;
      }
      final deja = _enCours[chemin];
      if (deja != null) return deja;
    }

    final demande = _signer(chemin);
    _enCours[chemin] = demande;
    try {
      return await demande;
    } finally {
      _enCours.remove(chemin);
    }
  }

  static Future<String> _signer(String chemin) async {
    try {
      final signee = await Supabase.instance.client.storage
          .from(_coffre)
          .createSignedUrl(chemin, 3600);
      // Gardée un peu moins d'une heure, pour ne jamais servir une
      // adresse qui expire entre l'affichage et le chargement.
      _cache[chemin] =
          _Signe(signee, DateTime.now().add(const Duration(minutes: 50)));
      return signee;
    } on StorageException catch (e) {
      if (e.statusCode == '403' || e.statusCode == '401') {
        throw const LienRefuse();
      }
      rethrow;
    }
  }

  /// À la déconnexion : les adresses signées d'une personne n'ont rien
  /// à faire en mémoire quand une autre se connecte sur le même téléphone.
  static void oublier() {
    _cache.clear();
    _enCours.clear();
  }
}

class _Signe {
  final String adresse;
  final DateTime expire;
  const _Signe(this.adresse, this.expire);
}
