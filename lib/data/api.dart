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

  /// Sans ce type, le navigateur télécharge le fichier au lieu de le
  /// montrer, et une vidéo refuse de se lire.
  String get typeMime => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'pdf' => 'application/pdf',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        '3gp' => 'video/3gpp',
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska',
        'avi' => 'video/x-msvideo',
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

  /// L'administrateur redonne un mot de passe à quelqu'un qui a perdu le
  /// sien. La base vérifie elle-même que l'appelant est bien admin :
  /// l'application ne détient aucun pouvoir spécial.
  static Future<String> adminChangerMotDePasse(
      String profilId, String nouveau) async {
    final r = await _db.rpc('admin_changer_mot_de_passe', params: {
      'p_profil': profilId,
      'p_nouveau': nouveau,
    });
    return '$r';
  }

  /// Change l'identifiant de connexion. Il sert aussi d'adresse interne,
  /// donc la base le met à jour aux trois endroits d'un seul coup.
  static Future<String> adminChangerIdentifiant(
      String profilId, String nouveau) async {
    final r = await _db.rpc('admin_changer_identifiant', params: {
      'p_profil': profilId,
      'p_nouveau': nouveau,
    });
    return '$r';
  }

  /// Tire un numéro d'accès à 8 chiffres encore libre. C'est la base
  /// qui vérifie l'unicité : deux admins qui créent en même temps ne
  /// peuvent pas tomber sur le même.
  static Future<String> nouveauNumeroAcces() async {
    final r = await _db.rpc('nouveau_numero_acces');
    return '$r';
  }

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

  /// C'est la base qui décide si le pointage est accepté : elle vérifie
  /// la distance à la ferme. Un téléphone modifié qui appellerait l'API
  /// directement se ferait refuser de la même façon.
  static Future<void> pointerArrivee(
      {double? latitude, double? longitude}) async {
    await _db.rpc('pointer_arrivee', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
    });
  }

  /// Ferme les pointages dont le telephone ne donne plus signe de vie.
  static Future<void> fermerPointagesMuets({int minutes = 30}) async {
    await _db.rpc('fermer_pointages_silencieux', params: {'p_minutes': minutes});
  }

  static Future<void> pointerSortie(
      {double? latitude, double? longitude, bool auto = false}) async {
    await _db.rpc('pointer_sortie', params: {
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_auto': auto,
    });
  }

  // ── SORTIES DE ZONE ET ITINÉRAIRE ──────────────────────────────────
  /// Les fois où quelqu'un a quitté sa ferme pendant qu'il était en
  /// ligne. C'est la base qui les écrit, pendant le suivi.
  static Future<List<SortieZone>> sorties({String? fermeId}) async {
    var q = _db.from('sorties_zone').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('moment', ascending: false).limit(200);
    return r.map<SortieZone>((m) => SortieZone.depuis(m)).toList();
  }

  /// Le chemin parcouru pendant un pointage, du plus ancien au plus
  /// récent. Le suivi s'arrête deux heures après la sortie.
  static Future<List<Trajet>> trajets(String pointageId) async {
    final r = await _db
        .from('trajets')
        .select()
        .eq('pointage_id', pointageId)
        .order('moment')
        .limit(500);
    return r.map<Trajet>((m) => Trajet.depuis(m)).toList();
  }

  /// L'administrateur a vu la sortie : elle ne clignote plus.
  static Future<void> marquerSortieVue(String id) => _db
      .from('sorties_zone')
      .update({'vu_par_admin': true}).eq('id', id);

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

  // ── CLIENTS REVENDEURS ET VENTES ───────────────────────────────────
  static Future<List<Client>> clients({String? fermeId}) async {
    var q = _db.from('clients').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('nom');
    return r.map<Client>((m) => Client.depuis(m)).toList();
  }

  static Future<void> creerClient(Map<String, dynamic> champs) =>
      _db.from('clients').insert(champs);

  static Future<void> majClient(String id, Map<String, dynamic> champs) =>
      _db.from('clients').update(champs).eq('id', id);

  static Future<void> supprimerClient(String id) =>
      _db.from('clients').delete().eq('id', id);

  static Future<List<Vente>> ventes({String? fermeId}) async {
    var q = _db.from('ventes').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false).limit(500);
    return r.map<Vente>((m) => Vente.depuis(m)).toList();
  }

  /// La vente et la recette qui va avec sont créées ensemble par la base :
  /// impossible d'avoir une facture sans l'argent dans les comptes.
  /// Rend le numéro de facture.
  static Future<String> enregistrerVente({
    required String clientId,
    required DateTime date,
    required int nbAlveoles,
    required int prixAlveole,
    required bool paye,
    String note = '',
  }) async {
    final r = await _db.rpc('enregistrer_vente', params: {
      'p_client': clientId,
      'p_date': iso(date),
      'p_nb_alveoles': nbAlveoles,
      'p_prix_alveole': prixAlveole,
      'p_paye': paye,
      'p_note': note,
    });
    if (r is List && r.isNotEmpty) return '${r.first['reference']}';
    return '';
  }

  static Future<void> supprimerVente(String id) =>
      _db.rpc('supprimer_vente', params: {'p_vente': id});

  static Future<void> majVente(String id, Map<String, dynamic> champs) =>
      _db.from('ventes').update(champs).eq('id', id);

  // ── SANTÉ : MORTALITÉ ET VACCINS ───────────────────────────────────
  static Future<List<Mortalite>> mortalites({String? fermeId}) async {
    var q = _db.from('mortalites').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date', ascending: false).limit(500);
    return r.map<Mortalite>((m) => Mortalite.depuis(m)).toList();
  }

  /// Une seule ligne par bâtiment et par jour : resaisir corrige.
  static Future<void> enregistrerMortalite(Map<String, dynamic> champs) =>
      _db.from('mortalites').upsert(champs, onConflict: 'batiment_id,date');

  static Future<void> supprimerMortalite(String id) =>
      _db.from('mortalites').delete().eq('id', id);

  static Future<List<Vaccination>> vaccinations({String? fermeId}) async {
    var q = _db.from('vaccinations').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('date_faite', ascending: false).limit(500);
    return r.map<Vaccination>((m) => Vaccination.depuis(m)).toList();
  }

  static Future<void> enregistrerVaccination(Map<String, dynamic> champs) =>
      _db.from('vaccinations').upsert(champs,
          onConflict: 'batiment_id,vaccin,age_jours');

  static Future<void> supprimerVaccination(String id) =>
      _db.from('vaccinations').delete().eq('id', id);

  // ── PHOTOS ─────────────────────────────────────────────────────────
  static Future<List<Photo>> photos({String? fermeId}) async {
    var q = _db.from('photos').select();
    if (fermeId != null) q = q.eq('ferme_id', fermeId);
    final r = await q.order('cree_le', ascending: false).limit(300);
    return r.map<Photo>((m) => Photo.depuis(m)).toList();
  }

  static Future<void> creerPhoto(Map<String, dynamic> champs) =>
      _db.from('photos').insert(champs);

  static Future<void> supprimerPhoto(String id) =>
      _db.from('photos').delete().eq('id', id);

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

  /// Envoie plusieurs images d'un coup et rend leurs adresses.
  static Future<List<String>> envoyerFichiers(
      List<FichierChoisi> fichiers, String dossier) async {
    final liens = <String>[];
    for (final f in fichiers) {
      liens.add(await envoyerFichier(f, dossier));
    }
    return liens;
  }
}
