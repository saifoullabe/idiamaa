import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../models/modeles.dart';

/// Une photo ou un document choisi par l'utilisateur, gardé sous forme
/// d'octets : c'est la seule forme qui marche à la fois sur le téléphone
/// et dans un navigateur, où les fichiers n'ont pas de chemin sur disque.
class FichierChoisi {
  final Uint8List octets;
  final String nom;

  const FichierChoisi(this.octets, this.nom);

  String get extension {
    final point = nom.lastIndexOf('.');
    if (point < 0 || point == nom.length - 1) return 'bin';
    return nom.substring(point + 1).toLowerCase();
  }

  /// Sans ce type, le navigateur télécharge le reçu au lieu de l'afficher.
  String get typeMime => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };
}

/// Tout ce que l'application demande à la base passe par ici.
class Api {
  static SupabaseClient get _db => Supabase.instance.client;

  // ── FERMES ─────────────────────────────────────────────────────────
  static Future<List<Ferme>> fermes() async {
    final r = await _db.from('fermes').select().order('nom');
    return r.map<Ferme>((m) => Ferme.depuis(m)).toList();
  }

  static Future<void> creerFerme({
    required String nom,
    String adresse = '',
    String ville = '',
    String notes = '',
    int prixAlveole = prixAlveoleDefaut,
  }) =>
      _db.from('fermes').insert({
        'nom': nom,
        'adresse': adresse,
        'ville': ville,
        'notes': notes,
        'prix_alveole': prixAlveole,
        'statut': 'Actif',
      });

  static Future<void> majFerme(String id, Map<String, dynamic> champs) =>
      _db.from('fermes').update(champs).eq('id', id);

  static Future<void> supprimerFerme(String id) =>
      _db.from('fermes').delete().eq('id', id);

  /// Le prix de l'alvéole se change sur la ferme ET sur ses bâtiments,
  /// sinon les bâtiments continuent de calculer avec l'ancien prix.
  static Future<void> changerPrixAlveole(String fermeId, int prix) async {
    await _db.from('fermes').update({'prix_alveole': prix}).eq('id', fermeId);
    await _db
        .from('batiments')
        .update({'prix_alveole': prix}).eq('ferme_id', fermeId);
  }

  // ── PROFILS ────────────────────────────────────────────────────────
  /// L'admin voit les fiches complètes ; les autres ne voient de leurs
  /// collègues que le nom, le rôle et le téléphone — pas le salaire.
  static Future<List<Profil>> profils({required bool complet}) async {
    final r = await _db
        .from(complet ? 'profils' : 'collegues')
        .select()
        .order('nom');
    return r.map<Profil>((m) => Profil.depuis(m)).toList();
  }

  static Future<Profil?> monProfil() async {
    final id = _db.auth.currentUser?.id;
    if (id == null) return null;
    final r = await _db.from('profils').select().eq('id', id).maybeSingle();
    return r == null ? null : Profil.depuis(r);
  }

  /// Crée le compte de connexion PUIS sa fiche.
  ///
  /// L'inscription passe par un client Supabase séparé : sans cela,
  /// l'administrateur serait déconnecté et se retrouverait connecté
  /// à la place de la personne qu'il vient de créer.
  static Future<void> creerUtilisateur({
    required String login,
    required String motDePasse,
    required String nom,
    required String prenom,
    required String role,
    String? fermeId,
    Map<String, dynamic> autresChamps = const {},
  }) async {
    final clientTemporaire =
        SupabaseClient(Config.supabaseUrl, Config.supabaseAnonKey);
    String? nouvelId;
    try {
      final reponse = await clientTemporaire.auth.signUp(
        email: Config.emailDe(login),
        password: motDePasse,
      );
      nouvelId = reponse.user?.id;
      await clientTemporaire.auth.signOut();
    } on AuthException catch (e) {
      await clientTemporaire.dispose();
      if (e.message.toLowerCase().contains('already')) {
        throw Exception('L’identifiant « $login » est déjà utilisé.');
      }
      throw Exception(e.message);
    }
    await clientTemporaire.dispose();

    if (nouvelId == null) {
      throw Exception(
          'Le compte n’a pas pu être créé. Dans Supabase → Authentication → '
          'Providers → Email, la case « Confirm email » doit être décochée.');
    }

    await _db.from('profils').insert({
      'id': nouvelId,
      'login': login.trim().toLowerCase(),
      'nom': nom,
      'prenom': prenom,
      'role': role,
      'ferme_id': fermeId,
      ...autresChamps,
    });
  }

  static Future<void> majProfil(String id, Map<String, dynamic> champs) =>
      _db.from('profils').update(champs).eq('id', id);

  static Future<void> supprimerProfil(String id) =>
      _db.from('profils').delete().eq('id', id);

  static Future<void> changerMotDePasse(String nouveau) =>
      _db.auth.updateUser(UserAttributes(password: nouveau));

  /// Attribue un gérant et des fermiers à une ferme, en une passe.
  static Future<void> attribuer({
    required String fermeId,
    required String? gerantId,
    required List<String> fermierIds,
  }) async {
    // On détache d'abord tout le monde de cette ferme…
    await _db
        .from('profils')
        .update({'ferme_id': null})
        .eq('ferme_id', fermeId)
        .neq('role', 'admin');
    // … puis on rattache ceux qui ont été cochés.
    if (gerantId != null) {
      await _db.from('profils').update({'ferme_id': fermeId}).eq('id', gerantId);
    }
    for (final f in fermierIds) {
      await _db.from('profils').update({'ferme_id': fermeId}).eq('id', f);
    }
    await _db.from('fermes').update({'gerant_id': gerantId}).eq('id', fermeId);
  }

  // ── BÂTIMENTS ──────────────────────────────────────────────────────
  static Future<List<Batiment>> batiments({String? fermeId}) async {
    var q = _db.from('batiments').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('nom');
    return r.map<Batiment>((m) => Batiment.depuis(m)).toList();
  }

  static Future<void> creerBatiment(Map<String, dynamic> champs) =>
      _db.from('batiments').insert(champs);

  static Future<void> majBatiment(String id, Map<String, dynamic> champs) =>
      _db.from('batiments').update(champs).eq('id', id);

  static Future<void> supprimerBatiment(String id) =>
      _db.from('batiments').delete().eq('id', id);

  // ── RECETTES ───────────────────────────────────────────────────────
  static Future<List<Recette>> recettes({String? fermeId}) async {
    var q = _db.from('recettes').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Recette>((m) => Recette.depuis(m)).toList();
  }

  static Future<void> creerRecette(Map<String, dynamic> champs) =>
      _db.from('recettes').insert(champs);

  static Future<void> supprimerRecette(String id) =>
      _db.from('recettes').delete().eq('id', id);

  // ── DÉPENSES ───────────────────────────────────────────────────────
  static Future<List<Depense>> depenses({String? fermeId}) async {
    var q = _db.from('depenses').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Depense>((m) => Depense.depuis(m)).toList();
  }

  static Future<void> creerDepense(Map<String, dynamic> champs) =>
      _db.from('depenses').insert(champs);

  static Future<void> supprimerDepense(String id) =>
      _db.from('depenses').delete().eq('id', id);

  // ── PRODUCTIONS (alvéoles) ─────────────────────────────────────────
  static Future<List<Production>> productions({String? fermeId}) async {
    var q = _db.from('productions').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Production>((m) => Production.depuis(m)).toList();
  }

  /// Une seule ligne par bâtiment et par jour : resaisir le même jour
  /// corrige la valeur au lieu d'en ajouter une, et le gérant qui repasse
  /// derrière son fermier remplace la saisie sans la dédoubler.
  static Future<void> enregistrerProduction({
    required String fermeId,
    required String batimentId,
    required String auteurId,
    required String roleAuteur,
    required DateTime date,
    required int nbAlveoles,
    required int prixAlveole,
  }) =>
      _db.from('productions').upsert({
        'ferme_id': fermeId,
        'batiment_id': batimentId,
        'auteur_id': auteurId,
        'role_auteur': roleAuteur,
        'date': iso(date),
        'nb_alveoles': nbAlveoles,
        'oeufs': nbAlveoles * oeufsParAlveole,
        'valeur': nbAlveoles * prixAlveole,
        'statut': Statut.aLaCreation(roleAuteur),
        'motif_rejet': '',
      }, onConflict: 'batiment_id,date');

  static Future<void> supprimerProduction(String id) =>
      _db.from('productions').delete().eq('id', id);

  // ── DÉPÔTS ─────────────────────────────────────────────────────────
  static Future<List<Depot>> depots({String? fermeId}) async {
    var q = _db.from('depots').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Depot>((m) => Depot.depuis(m)).toList();
  }

  static Future<void> creerDepot(Map<String, dynamic> champs) =>
      _db.from('depots').insert(champs);

  static Future<void> supprimerDepot(String id) =>
      _db.from('depots').delete().eq('id', id);

  // ── VALIDATION (commun à recettes, dépenses, productions, dépôts) ──
  /// Chaque saisie n'est validée que par l'échelon juste au-dessus :
  /// celle d'un fermier par son gérant, celle d'un gérant par l'admin.
  /// Une fois validée, elle compte dans les totaux — nulle part ailleurs.
  static Future<void> valider(String table, List<String> ids,
      {required String roleValidateur}) async {
    if (ids.isEmpty) return;
    await _db.from(table).update(
        {'statut': Statut.valide, 'motif_rejet': ''}).inFilter('id', ids);
  }

  static Future<void> rejeter(String table, List<String> ids, String motif) async {
    if (ids.isEmpty) return;
    await _db.from(table).update({
      'statut': Statut.rejete,
      'motif_rejet': motif,
    }).inFilter('id', ids);
  }

  // ── POINTAGE ───────────────────────────────────────────────────────
  static Future<Pointage?> pointageEnCours(String profilId) async {
    final r = await _db
        .from('pointages')
        .select()
        .eq('profil_id', profilId)
        .eq('statut', 'en_cours')
        .order('debut', ascending: false)
        .limit(1)
        .maybeSingle();
    return r == null ? null : Pointage.depuis(r);
  }

  static Future<List<Pointage>> pointages({
    String? profilId,
    String? fermeId,
    int limite = 200,
  }) async {
    var q = _db.from('pointages').select();
    if (profilId != null) q = q.eq('profil_id', profilId);
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('debut', ascending: false).limit(limite);
    return r.map<Pointage>((m) => Pointage.depuis(m)).toList();
  }

  static Future<List<Pointage>> pointagesEnCours() async {
    final r = await _db
        .from('pointages')
        .select()
        .eq('statut', 'en_cours')
        .order('debut', ascending: false);
    return r.map<Pointage>((m) => Pointage.depuis(m)).toList();
  }

  static Future<void> pointerArrivee(String profilId, String? fermeId) =>
      _db.from('pointages').insert({
        'profil_id': profilId,
        'ferme_id': fermeId,
        'debut': DateTime.now().toUtc().toIso8601String(),
        'statut': 'en_cours',
      });

  static Future<void> pointerSortie(Pointage p) {
    final fin = DateTime.now();
    return _db.from('pointages').update({
      'fin': fin.toUtc().toIso8601String(),
      'duree': fin.difference(p.debut.toLocal()).inSeconds,
      'statut': 'termine',
    }).eq('id', p.id);
  }

  // ── STOCKS ─────────────────────────────────────────────────────────
  static Future<List<Stock>> stocks({String? fermeId}) async {
    var q = _db.from('stocks').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('nom');
    return r.map<Stock>((m) => Stock.depuis(m)).toList();
  }

  static Future<void> creerStock(Map<String, dynamic> champs) =>
      _db.from('stocks').insert(champs);

  static Future<void> majStock(String id, Map<String, dynamic> champs) =>
      _db.from('stocks').update(champs).eq('id', id);

  static Future<void> supprimerStock(String id) =>
      _db.from('stocks').delete().eq('id', id);

  /// La base fait le calcul et refuse une sortie plus grosse que le stock.
  static Future<double> bougerStock({
    required String stockId,
    required bool entree,
    required double quantite,
    String note = '',
  }) async {
    final r = await _db.rpc('bouger_stock', params: {
      'p_stock': stockId,
      'p_type': entree ? 'entree' : 'sortie',
      'p_qte': quantite,
      'p_note': note,
    });
    return double.tryParse('$r') ?? 0;
  }

  static Future<List<MouvementStock>> mouvements(String stockId) async {
    final r = await _db
        .from('mouvements_stock')
        .select()
        .eq('stock_id', stockId)
        .order('cree_le', ascending: false)
        .limit(50);
    return r.map<MouvementStock>((m) => MouvementStock.depuis(m)).toList();
  }

  // ── SIGNALEMENTS ───────────────────────────────────────────────────
  static Future<List<Signalement>> signalements({String? fermeId}) async {
    var q = _db.from('signalements').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Signalement>((m) => Signalement.depuis(m)).toList();
  }

  static Future<void> creerSignalement(Map<String, dynamic> champs) =>
      _db.from('signalements').insert(champs);

  static Future<void> majSignalement(String id, Map<String, dynamic> champs) =>
      _db.from('signalements').update(champs).eq('id', id);

  // ── RAPPORTS ───────────────────────────────────────────────────────
  static Future<List<Rapport>> rapports({String? fermeId}) async {
    var q = _db.from('rapports').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false);
    return r.map<Rapport>((m) => Rapport.depuis(m)).toList();
  }

  static Future<void> creerRapport(Map<String, dynamic> champs) =>
      _db.from('rapports').insert(champs);

  static Future<void> supprimerRapport(String id) =>
      _db.from('rapports').delete().eq('id', id);

  // ── ARTICLES PERSONNALISÉS ─────────────────────────────────────────
  static Future<Map<String, List<String>>> articlesPerso() async {
    final r = await _db.from('articles_perso').select();
    final parCategorie = <String, List<String>>{};
    for (final m in r) {
      parCategorie
          .putIfAbsent('${m['categorie']}', () => [])
          .add('${m['nom']}');
    }
    return parCategorie;
  }

  static Future<void> ajouterArticle(
          String? fermeId, String categorie, String nom) =>
      _db.from('articles_perso').upsert({
        'ferme_id': fermeId,
        'categorie': categorie,
        'nom': nom,
      }, onConflict: 'ferme_id,categorie,nom');

  // ── FICHIERS (photos, pièces d'identité, reçus) ────────────────────
  static Future<String> envoyerFichier(
      FichierChoisi fichier, String dossier) async {
    final chemin =
        '$dossier/${DateTime.now().microsecondsSinceEpoch}.${fichier.extension}';
    await _db.storage.from('documents').uploadBinary(
          chemin,
          fichier.octets,
          fileOptions: FileOptions(contentType: fichier.typeMime),
        );
    return _db.storage.from('documents').getPublicUrl(chemin);
  }
}
