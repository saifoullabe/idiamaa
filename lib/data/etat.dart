import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/localisation.dart';
import '../models/modeles.dart';
import 'api.dart';
import 'presence.dart' as suivi;

/// L'état de l'application : qui est connecté, et tout ce qu'il a le
/// droit de voir. Une seule source, rafraîchie d'un coup.
class Etat extends ChangeNotifier {
  Profil? moi;
  bool chargement = false;
  String? erreur;

  List<Ferme> fermes = [];
  List<Profil> personnes = [];
  List<Batiment> batiments = [];
  List<Recette> recettes = [];
  List<Depense> depenses = [];
  List<Production> productions = [];
  List<Depot> depots = [];
  List<Stock> stocks = [];
  List<Signalement> signalements = [];
  List<Rapport> rapports = [];
  List<Photo> photos = [];
  List<Client> clients = [];
  List<Vente> ventes = [];
  List<SortieZone> sorties = [];
  List<Mortalite> mortalites = [];
  List<Vaccination> vaccinations = [];
  List<Pointage> pointages = [];
  List<Pointage> pointagesEnCours = [];
  Pointage? monPointage;
  Map<String, List<String>> articlesPerso = {};

  bool get connecte => moi != null;
  String get role => moi?.role ?? Role.fermier;
  String? get maFermeId => moi?.fermeId;
  bool get estAdmin => role == Role.admin;
  bool get estGerant => role == Role.gerant;
  bool get estFermier => role == Role.fermier;

  Ferme? get maFerme => maFermeId == null
      ? null
      : fermes.cast<Ferme?>().firstWhere((f) => f?.id == maFermeId,
          orElse: () => null);

  bool get enLigne => monPointage != null;

  /// Le fermier doit avoir pointé son arrivée avant de saisir quoi que ce soit.
  bool get peutSaisir {
    if (moi == null || moi!.suspendu) return false;
    if (estFermier && !enLigne) return false;
    return true;
  }

  String? get raisonBlocage {
    if (moi == null) return 'Non connecté';
    if (moi!.suspendu) return 'Compte suspendu — aucune saisie possible.';
    if (estFermier && !enLigne) {
      return 'Pointez votre arrivée avant de saisir.';
    }
    return null;
  }

  // ── Connexion ──────────────────────────────────────────────────────
  Future<String?> connexion(String login, String motDePasse) async {
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: Config.emailDe(login),
        password: motDePasse,
      );
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid')) return 'Identifiant ou mot de passe incorrect';
      if (m.contains('confirm')) {
        return 'Ce compte n’est pas encore activé. Contactez l’administrateur.';
      }
      return e.message;
    } catch (e) {
      return 'Connexion impossible. Vérifiez votre réseau.';
    }

    final profil = await Api.monProfil();
    if (profil == null) {
      await Supabase.instance.client.auth.signOut();
      return 'Ce compte n’existe plus. Contactez l’administrateur.';
    }
    if (profil.fermeId != null) {
      final toutesFermes = await Api.fermes();
      final f = toutesFermes.cast<Ferme?>().firstWhere(
          (x) => x?.id == profil.fermeId,
          orElse: () => null);
      if (f != null && f.suspendue && profil.role != Role.admin) {
        await Supabase.instance.client.auth.signOut();
        return 'La ferme ${f.nom} est suspendue. Contactez l’administrateur.';
      }
    }
    moi = profil;
    notifyListeners();
    await rafraichir();
    return null;
  }

  Future<void> reprendreSession() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    Profil? profil;
    try {
      profil = await Api.monProfil().timeout(const Duration(seconds: 20));
    } catch (e) {
      // Pas de réseau au démarrage : on ne déconnecte pas. Déconnecter
      // ici obligerait à retaper son mot de passe dans une zone où le
      // réseau manque justement — exactement au mauvais moment.
      erreur = 'Pas de connexion. Réessayez quand le réseau revient.';
      notifyListeners();
      return;
    }
    if (profil == null) {
      await deconnexion();
      return;
    }
    moi = profil;
    notifyListeners();
    await rafraichir();
  }

  Future<void> deconnexion() async {
    await Supabase.instance.client.auth.signOut();
    moi = null;
    fermes = [];
    personnes = [];
    batiments = [];
    recettes = [];
    depenses = [];
    productions = [];
    depots = [];
    stocks = [];
    signalements = [];
    rapports = [];
    photos = [];
    clients = [];
    ventes = [];
    sorties = [];
    mortalites = [];
    vaccinations = [];
    pointages = [];
    pointagesEnCours = [];
    monPointage = null;
    notifyListeners();
  }

  // ── Chargement ─────────────────────────────────────────────────────
  Future<void> rafraichir() async {
    if (moi == null) return;
    chargement = true;
    erreur = null;
    notifyListeners();

    final portee = estAdmin ? null : maFermeId;
    // Avant de lire les présences, on ferme celles dont le téléphone
    // s'est tu : sinon on afficherait comme « au travail » quelqu'un
    // dont l'application est éteinte depuis une heure.
    await fermerPointagesMuets();

    // Chaque lecture est isolée : si une table manque ou refuse l'accès,
    // elle revient vide et le reste de l'écran s'affiche quand même.
    // Avant, une seule requête en échec noircissait toute l'application.
    final manquants = <String>[];
    int tentees = 0, echouees = 0;

    // « actuel » est ce qui est déjà affiché. En cas d'échec réseau on le
    // garde : avant, un rafraîchissement raté vidait l'écran et le fermier
    // croyait ses saisies perdues.
    Future<T> lire<T>(String quoi, Future<T> Function() requete, T repli,
        {T? actuel}) async {
      tentees++;
      try {
        // Sans délai, une requête partie sur un réseau qui ne répond plus
        // laisse l'application tourner indéfiniment sur son sablier.
        return await requete().timeout(const Duration(seconds: 25));
      } catch (e) {
        echouees++;
        final t = e.toString();
        // « Table introuvable » veut dire qu'un fichier SQL n'a pas été
        // lancé : on le nomme, c'est réparable en une minute.
        if (t.contains('PGRST205') || t.contains('does not exist')) {
          manquants.add(quoi);
          // La table n'existe pas : garder l'ancien contenu induirait en
          // erreur, on rend bien le repli vide.
          return repli;
        }
        return actuel ?? repli;
      }
    }

    final resultats = await Future.wait<dynamic>([
      lire('fermes', Api.fermes, <Ferme>[], actuel: fermes),
      lire('profils', () => Api.profils(complet: estAdmin), <Profil>[],
          actuel: personnes),
      lire('bâtiments', () => Api.batiments(fermeId: portee), <Batiment>[],
          actuel: batiments),
      lire('recettes', () => Api.recettes(fermeId: portee), <Recette>[],
          actuel: recettes),
      lire('dépenses', () => Api.depenses(fermeId: portee), <Depense>[],
          actuel: depenses),
      lire('productions', () => Api.productions(fermeId: portee),
          <Production>[], actuel: productions),
      lire('dépôts', () => Api.depots(fermeId: portee), <Depot>[],
          actuel: depots),
      lire('stocks', () => Api.stocks(fermeId: portee), <Stock>[],
          actuel: stocks),
      lire('signalements', () => Api.signalements(fermeId: portee),
          <Signalement>[], actuel: signalements),
      lire('rapports', () => Api.rapports(fermeId: portee), <Rapport>[],
          actuel: rapports),
      lire('pointages', () => Api.pointages(fermeId: portee), <Pointage>[],
          actuel: pointages),
      lire('présences', Api.pointagesEnCours, <Pointage>[],
          actuel: pointagesEnCours),
      // Le pointage décide si le fermier peut saisir : une coupure réseau
      // ne doit surtout pas le faire passer pour hors ligne.
      lire('mon pointage', () => Api.pointageEnCours(moi!.id), null,
          actuel: monPointage),
      lire('photos', () => Api.photos(fermeId: portee), <Photo>[],
          actuel: photos),
      lire('clients', () => Api.clients(fermeId: portee), <Client>[],
          actuel: clients),
      lire('ventes', () => Api.ventes(fermeId: portee), <Vente>[],
          actuel: ventes),
      lire('mortalités', () => Api.mortalites(fermeId: portee), <Mortalite>[],
          actuel: mortalites),
      lire('vaccinations', () => Api.vaccinations(fermeId: portee),
          <Vaccination>[], actuel: vaccinations),
      lire('articles', Api.articlesPerso, <String, List<String>>{},
          actuel: articlesPerso),
      lire('mon profil', Api.monProfil, null, actuel: moi),
      lire('sorties de zone', () => Api.sorties(fermeId: portee),
          <SortieZone>[], actuel: sorties),
    ]);

    fermes = resultats[0] as List<Ferme>;
    personnes = resultats[1] as List<Profil>;
    batiments = resultats[2] as List<Batiment>;
    recettes = resultats[3] as List<Recette>;
    depenses = resultats[4] as List<Depense>;
    productions = resultats[5] as List<Production>;
    depots = resultats[6] as List<Depot>;
    stocks = resultats[7] as List<Stock>;
    signalements = resultats[8] as List<Signalement>;
    rapports = resultats[9] as List<Rapport>;
    pointages = resultats[10] as List<Pointage>;
    pointagesEnCours = resultats[11] as List<Pointage>;
    monPointage = resultats[12] as Pointage?;
    photos = resultats[13] as List<Photo>;
    clients = resultats[14] as List<Client>;
    ventes = resultats[15] as List<Vente>;
    mortalites = resultats[16] as List<Mortalite>;
    vaccinations = resultats[17] as List<Vaccination>;
    articlesPerso = resultats[18] as Map<String, List<String>>;
    final profilFrais = resultats[19] as Profil?;
    if (profilFrais != null) moi = profilFrais;
    sorties = resultats[20] as List<SortieZone>;

    // Tout est tombé : c'est le réseau, pas une table absente.
    if (echouees == tentees) {
      erreur = 'Pas de connexion. Les données affichées peuvent dater.';
    } else if (manquants.isNotEmpty) {
      erreur = manquants.length == 1
          ? 'La partie « ${manquants.first} » n’est pas encore installée '
              'dans la base. Le reste fonctionne.'
          : '${manquants.length} parties ne sont pas encore installées '
              'dans la base (${manquants.join(', ')}). Le reste fonctionne.';
    } else if (echouees > 0) {
      erreur = '$echouees information(s) n’ont pas pu être chargées. '
          'Tirez vers le bas pour réessayer.';
    }

    chargement = false;
    notifyListeners();
  }

  static String _lisible(Object e) {
    final t = e.toString();
    // Le nom du serveur n'a même pas pu être résolu : la requête n'est
    // jamais partie, on peut réessayer sans risque de doublon.
    if (t.contains('Failed host lookup')) {
      return 'Pas de connexion internet. Rien n’a été envoyé, '
          'vous pouvez réessayer.';
    }
    // Coupure PENDANT l'envoi, ou délai dépassé : le serveur a peut-être
    // tout reçu. On ne dit jamais « échec » sans cet avertissement.
    if (e is TimeoutException ||
        t.contains('TimeoutException') ||
        t.contains('ClientException') ||
        t.contains('SocketException')) {
      return 'Le réseau a coupé pendant l’envoi. Regardez la liste avant '
          'de ressaisir : l’enregistrement est peut-être passé.';
    }
    if (t.contains('row-level security') || t.contains('violates')) {
      return 'Action refusée : vous n’avez pas le droit de faire cela.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  /// Exécute une écriture puis recharge, en rendant l'erreur lisible.
  ///
  /// Les deux temps sont séparés exprès. Quand ils partageaient le même
  /// « try », un rechargement raté faisait passer une écriture réussie
  /// pour un échec : la personne recommençait et créait un doublon, ou
  /// se heurtait à « déjà utilisé » sans comprendre.
  Future<String?> agir(Future<void> Function() action) async {
    try {
      // Large, car une saisie peut emporter une vidéo. Mais borné : sans
      // cela, le bouton Enregistrer tourne sans fin et la personne finit
      // par ressaisir, créant un doublon.
      await action().timeout(const Duration(minutes: 3));
    } catch (e) {
      final message = _lisible(e);
      // Le délai n'annule pas l'envoi déjà parti : l'écriture est
      // peut-être passée. On recharge donc quand même, pour que la
      // personne VOIE si c'est enregistré au lieu de ressaisir et de
      // créer un doublon.
      try {
        await rafraichir();
      } catch (_) {}
      erreur = message;
      chargement = false;
      notifyListeners();
      return message;
    }

    try {
      await rafraichir();
    } catch (_) {
      erreur = 'C’est enregistré, mais la liste n’a pas pu être rechargée. '
          'Tirez vers le bas pour la rafraîchir.';
      chargement = false;
      notifyListeners();
    }
    return null;
  }

  // ── Pointage ───────────────────────────────────────────────────────
  /// Le fermier ne peut passer en ligne que depuis la ferme. La position
  /// est prise ici, mais c'est la base qui tranche.
  Future<String?> basculerPointage() async {
    if (moi == null) return 'Non connecté';
    if (moi!.suspendu) return 'Compte suspendu — action impossible.';

    final sortie = monPointage != null;
    Position2? pos;

    // On demande la position quand la ferme en a une d'enregistrée.
    final f = maFerme;
    if (f?.latitude != null && f?.longitude != null) {
      pos = await Localisation.position();
      // À l'arrivée, pas de position = pas de pointage pour un fermier.
      if (!sortie && estFermier && !pos.utilisable) {
        return pos.explication;
      }
    }

    final erreur = await agir(() async {
      if (sortie) {
        await Api.pointerSortie(
            latitude: pos?.latitude, longitude: pos?.longitude);
      } else {
        await Api.pointerArrivee(
            latitude: pos?.latitude, longitude: pos?.longitude);
      }
    });
    if (erreur != null) return erreur;

    // Le suivi continu ne tourne que pendant le pointage d'un fermier
    // sur une ferme dont la position est enregistrée.
    if (sortie) {
      await suivi.Presence.arreter();
    } else if (estFermier && f?.latitude != null) {
      await suivi.Presence.demarrer(surSortie: (motif) async {
        await rafraichir();
        messageSortieAuto = motif;
        notifyListeners();
      });
    }
    return null;
  }

  /// Ce que la base a dit quand elle a mis quelqu'un hors ligne tout seul.
  /// L'écran le lit, l'affiche, puis le remet à null.
  String? messageSortieAuto;

  /// Ferme les pointages dont le téléphone ne donne plus de nouvelles.
  /// Appelé au chargement par l'admin et le gérant : pas besoin de
  /// planificateur, ceux qui regardent font le ménage.
  Future<void> fermerPointagesMuets() async {
    if (!estAdmin && !estGerant) return;
    try {
      // Borné : ce ménage précède les 21 lectures. Sans délai, un réseau
      // qui accepte la connexion sans jamais répondre bloquait ici — et
      // le bouton de rafraîchissement étant désactivé pendant le
      // chargement, il ne restait qu'à tuer l'application.
      await Api.fermerPointagesMuets().timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Vérifie que la personne est toujours sur place. Si elle a quitté la
  /// ferme, on la met hors ligne toute seule.
  /// Rend la distance en mètres, ou null si le contrôle ne s'applique pas.
  Future<double?> verifierPresence() async {
    if (moi == null || monPointage == null || !estFermier) return null;
    final f = maFerme;
    if (f?.latitude == null || f?.longitude == null) return null;

    final pos = await Localisation.position();
    if (!pos.utilisable) return null;

    final d = Localisation.distance(
        f!.latitude!, f.longitude!, pos.latitude!, pos.longitude!);

    if (d > f.rayonMetres) {
      await agir(() => Api.pointerSortie(
            latitude: pos.latitude,
            longitude: pos.longitude,
            auto: true,
          ));
    }
    return d;
  }

  // ── Aides de lecture ───────────────────────────────────────────────
  Ferme? ferme(String? id) => id == null
      ? null
      : fermes.cast<Ferme?>().firstWhere((f) => f?.id == id, orElse: () => null);

  Profil? personne(String? id) => id == null
      ? null
      : personnes.cast<Profil?>()
          .firstWhere((p) => p?.id == id, orElse: () => null);

  Batiment? batiment(String? id) => id == null
      ? null
      : batiments.cast<Batiment?>()
          .firstWhere((b) => b?.id == id, orElse: () => null);

  String nomFerme(String? id) => ferme(id)?.nom ?? '—';
  String nomPersonne(String? id) => personne(id)?.nomComplet ?? 'Utilisateur';

  List<Batiment> batimentsDe(String? fermeId) =>
      batiments.where((b) => b.fermeId == fermeId).toList();

  // ── Le cheptel vivant ──────────────────────────────────────────────
  /// Toutes les poules mortes depuis la mise en place du bâtiment.
  int mortsCumules(String batimentId) => mortalites
      .where((m) => m.batimentId == batimentId)
      .fold<int>(0, (s, m) => s + m.nombre);

  /// L'effectif réellement présent : l'arrivage moins les morts déclarées.
  /// C'est lui qui doit servir au taux de ponte, jamais l'effectif de départ.
  int effectifVivant(Batiment b) {
    final v = b.nbPoules - mortsCumules(b.id);
    return v < 0 ? 0 : v;
  }

  /// Mortalité cumulée en % de l'effectif de départ.
  double tauxMortalite(Batiment b) =>
      b.nbPoules > 0 ? mortsCumules(b.id) / b.nbPoules * 100 : 0;

  int mortsDuJour(String batimentId, DateTime j) => mortalites
      .where((m) =>
          m.batimentId == batimentId && m.date != null && iso(m.date!) == iso(j))
      .fold<int>(0, (s, m) => s + m.nombre);

  /// Les morts des sept derniers jours — le signal qui compte vraiment.
  int mortsSemaine(String batimentId) {
    final depuis = aujourdhui().subtract(const Duration(days: 7));
    return mortalites
        .where((m) =>
            m.batimentId == batimentId &&
            m.date != null &&
            !m.date!.isBefore(depuis))
        .fold<int>(0, (s, m) => s + m.nombre);
  }

  Vaccination? vaccinFait(String batimentId, String vaccin, int ageJours) =>
      vaccinations.cast<Vaccination?>().firstWhere(
            (v) =>
                v!.batimentId == batimentId &&
                v.vaccin == vaccin &&
                v.ageJours == ageJours,
            orElse: () => null,
          );

  List<Profil> gerants() => personnes.where((p) => p.estGerant).toList();
  List<Profil> fermiers() => personnes.where((p) => p.estFermier).toList();
  List<Profil> fermiersDe(String fermeId) =>
      personnes.where((p) => p.estFermier && p.fermeId == fermeId).toList();

  // ── Ce que le gérant doit valider (saisies des fermiers) ───────────
  int get aValiderGerant => estGerant
      ? recettes.where((r) => r.statut == Statut.attenteGerant).length +
          depenses.where((d) => d.statut == Statut.attenteGerant).length +
          productions.where((p) => p.statut == Statut.attenteGerant).length +
          depots.where((d) => d.statut == Statut.attenteGerant).length
      : 0;

  // ── Ce que l'admin doit valider (saisies des gérants) ──────────────
  int get aValiderAdmin => estAdmin
      ? recettes.where((r) => r.statut == Statut.attenteAdmin).length +
          depenses.where((d) => d.statut == Statut.attenteAdmin).length +
          productions.where((p) => p.statut == Statut.attenteAdmin).length +
          depots.where((d) => d.statut == Statut.attenteAdmin).length
      : 0;

  int get aValider => estAdmin ? aValiderAdmin : aValiderGerant;

  /// Le statut qu'attend une saisie pour être validée par moi.
  String get statutAValider =>
      estAdmin ? Statut.attenteAdmin : Statut.attenteGerant;

  // ── Chiffres ───────────────────────────────────────────────────────
  int totalRecettes({String? fermeId, DateTime? mois}) => recettes
      .where((r) =>
          r.statut == Statut.valide &&
          (fermeId == null || r.fermeId == fermeId) &&
          _memeMois(r.date, mois))
      .fold<int>(0, (s, r) => s + r.montant);

  int totalDepenses({String? fermeId, DateTime? mois, String? categorie}) =>
      depenses
          .where((d) =>
              d.statut == Statut.valide &&
              (fermeId == null || d.fermeId == fermeId) &&
              (categorie == null || d.categorie == categorie) &&
              _memeMois(d.date, mois))
          .fold<int>(0, (s, d) => s + d.montant);

  /// Les dépôts que l'administration a envoyés à la ferme.
  int totalDepotsRecus({String? fermeId, DateTime? mois}) => depots
      .where((d) =>
          d.statut == Statut.valide &&
          d.roleAuteur == Role.admin &&
          (fermeId == null || d.fermeId == fermeId) &&
          _memeMois(d.date, mois))
      .fold<int>(0, (s, d) => s + d.montant);

  /// Les dépôts que la ferme a fait remonter à l'administration.
  int totalDepotsEnvoyes({String? fermeId}) => depots
      .where((d) =>
          d.statut == Statut.valide &&
          d.roleAuteur != Role.admin &&
          (fermeId == null || d.fermeId == fermeId))
      .fold<int>(0, (s, d) => s + d.montant);

  int solde({String? fermeId}) =>
      totalRecettes(fermeId: fermeId) +
      totalDepotsRecus(fermeId: fermeId) -
      totalDepenses(fermeId: fermeId);

  int oeufsDuJour({String? fermeId, DateTime? date}) {
    final j = date ?? aujourdhui();
    return productions
        .where((p) =>
            (fermeId == null || p.fermeId == fermeId) &&
            p.date != null &&
            iso(p.date!) == iso(j))
        .fold<int>(0, (s, p) => s + p.oeufs);
  }

  static bool _memeMois(DateTime? d, DateTime? mois) {
    if (mois == null) return true;
    if (d == null) return false;
    return d.year == mois.year && d.month == mois.month;
  }

  /// Les 7 derniers jours de production, pour la courbe du tableau de bord.
  List<({DateTime jour, int oeufs, int valeur})> serieProduction(
      {String? fermeId, int jours = 7}) {
    final base = aujourdhui();
    return List.generate(jours, (i) {
      final j = base.subtract(Duration(days: jours - 1 - i));
      final lot = productions.where((p) =>
          (fermeId == null || p.fermeId == fermeId) &&
          p.date != null &&
          iso(p.date!) == iso(j));
      return (
        jour: j,
        oeufs: lot.fold<int>(0, (s, p) => s + p.oeufs),
        valeur: lot.fold<int>(0, (s, p) => s + p.valeur),
      );
    });
  }

  /// Recettes et dépenses des 6 derniers mois.
  List<({DateTime mois, int recettes, int depenses})> serieMensuelle(
      {String? fermeId, int mois = 6}) {
    final n = DateTime.now();
    return List.generate(mois, (i) {
      final m = DateTime(n.year, n.month - (mois - 1 - i));
      return (
        mois: m,
        recettes: totalRecettes(fermeId: fermeId, mois: m),
        depenses: totalDepenses(fermeId: fermeId, mois: m),
      );
    });
  }
}
