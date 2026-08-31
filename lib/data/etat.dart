import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../models/modeles.dart';
import 'api.dart';

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
    final profil = await Api.monProfil();
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
    try {
      final resultats = await Future.wait([
        Api.fermes(),
        Api.profils(complet: estAdmin),
        Api.batiments(fermeId: portee),
        Api.recettes(fermeId: portee),
        Api.depenses(fermeId: portee),
        Api.productions(fermeId: portee),
        Api.depots(fermeId: portee),
        Api.stocks(fermeId: portee),
        Api.signalements(fermeId: portee),
        Api.rapports(fermeId: portee),
        Api.pointages(fermeId: portee, profilId: null),
        Api.pointagesEnCours(),
        Api.pointageEnCours(moi!.id),
        Api.articlesPerso(),
        Api.monProfil(),
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
      articlesPerso = resultats[13] as Map<String, List<String>>;
      final profilFrais = resultats[14] as Profil?;
      if (profilFrais != null) moi = profilFrais;
    } catch (e) {
      erreur = _lisible(e);
    }
    chargement = false;
    notifyListeners();
  }

  static String _lisible(Object e) {
    final t = e.toString();
    if (t.contains('SocketException') ||
        t.contains('Failed host lookup') ||
        t.contains('ClientException')) {
      return 'Pas de connexion internet. Les données affichées peuvent dater.';
    }
    if (t.contains('row-level security') || t.contains('violates')) {
      return 'Action refusée : vous n’avez pas le droit de faire cela.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  /// Exécute une écriture puis recharge, en rendant l'erreur lisible.
  Future<String?> agir(Future<void> Function() action) async {
    try {
      await action();
      await rafraichir();
      return null;
    } catch (e) {
      return _lisible(e);
    }
  }

  // ── Pointage ───────────────────────────────────────────────────────
  Future<String?> basculerPointage() async {
    if (moi == null) return 'Non connecté';
    if (moi!.suspendu) return 'Compte suspendu — action impossible.';
    return agir(() async {
      if (monPointage != null) {
        await Api.pointerSortie(monPointage!);
      } else {
        await Api.pointerArrivee(moi!.id, moi!.fermeId);
      }
    });
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
