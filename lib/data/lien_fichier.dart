import 'package:supabase_flutter/supabase_flutter.dart';

/// Transforme l'adresse d'un fichier en adresse signée, valable une heure.
///
/// Jusqu'ici le coffre était PUBLIC : l'adresse d'une photo, d'une pièce
/// d'identité ou d'un contrat suffisait à l'ouvrir, sans compte, depuis
/// n'importe où dans le monde. Fermer le coffre casserait toutes les
/// adresses déjà enregistrées en base — on ne les change donc pas : on
/// en extrait le chemin et on demande à Supabase une adresse signée au
/// moment de l'affichage.
///
/// Les adresses signées sont gardées en mémoire : sans cela, chaque
/// défilement d'une galerie redemanderait la même signature au serveur,
/// ce qui est exactement ce qu'il ne faut pas faire sur un réseau faible.
class LienFichier {
  static const _marqueur = '/storage/v1/object/public/documents/';
  static const _coffre = 'documents';

  /// chemin -> (adresse signée, moment où elle expire)
  static final Map<String, _Signe> _cache = {};

  /// Le chemin dans le coffre, ou null si cette adresse n'en vient pas
  /// (une image d'un autre serveur, par exemple).
  static String? cheminDe(String adresse) {
    final i = adresse.indexOf(_marqueur);
    if (i < 0) return null;
    final brut = adresse.substring(i + _marqueur.length);
    // Supabase ajoute parfois « ?t=... » : le chemin s'arrête avant.
    final q = brut.indexOf('?');
    return Uri.decodeFull(q < 0 ? brut : brut.substring(0, q));
  }

  /// L'adresse à donner à Image.network. Rend l'adresse d'origine si ce
  /// n'est pas un fichier du coffre, ou si la signature échoue — ainsi
  /// un coffre encore public continue de fonctionner.
  static Future<String> affichable(String adresse) async {
    final chemin = cheminDe(adresse);
    if (chemin == null) return adresse;

    final garde = _cache[chemin];
    if (garde != null && garde.expire.isAfter(DateTime.now())) {
      return garde.adresse;
    }
    try {
      final signee = await Supabase.instance.client.storage
          .from(_coffre)
          .createSignedUrl(chemin, 3600);
      // On garde un peu moins d'une heure, pour ne jamais servir une
      // adresse qui expire entre l'affichage et le chargement.
      _cache[chemin] = _Signe(
          signee, DateTime.now().add(const Duration(minutes: 50)));
      return signee;
    } catch (_) {
      return adresse;
    }
  }

  /// À la déconnexion : les adresses signées d'une personne n'ont rien
  /// à faire en mémoire quand une autre se connecte sur le même téléphone.
  static void oublier() => _cache.clear();
}

class _Signe {
  final String adresse;
  final DateTime expire;
  const _Signe(this.adresse, this.expire);
}
