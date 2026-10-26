import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/comparaison.dart';
import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/graphiques.dart';

/// Les chiffres qui décident si une ferme avicole gagne de l'argent.
/// Tout est calculé à partir des saisies validées — rien n'est saisi ici.
class EcranAnalyse extends StatefulWidget {
  const EcranAnalyse({super.key});

  @override
  State<EcranAnalyse> createState() => _EcranAnalyseState();
}

class _EcranAnalyseState extends State<EcranAnalyse> {
  int _jours = 30;
  String? _ferme;

  // ── Les pourcentages de ponte ──────────────────────────────────────
  // Ils sont calculés par la BASE, qui lit toutes les mortalités et
  // toutes les productions. Le téléphone n'en charge qu'une partie : le
  // taux qu'il calculait lui-même n'était pas le même pour le gérant et
  // pour l'administrateur, et il baissait tout seul avec le temps.
  // Voir sql/17_idiama_ponte.sql.
  String? _cle;
  Ponte? _periode;
  PonteComparee? _ponte;
  Map<String, Ponte>? _parBatiment;
  Panne? _panne;

  /// Le numéro de la demande en cours. Une réponse d'un numéro périmé
  /// est jetée : sans ce compteur, deux demandes identiques pouvaient
  /// cohabiter et la plus LENTE gagnait — le rafraîchissement
  /// réaffichait un chiffre plus vieux que celui d'avant.
  int _demande = 0;

  /// Redemande les chiffres dès que la période, la ferme ou les données
  /// changent. Le tour de lecture est dans la clé : sinon « Cheptel » se
  /// rafraîchissait et « Taux de ponte » restait figé sur l'ancien.
  void _assurerPonte(String? ferme, int jours, int tour) {
    final cle = '${ferme ?? 'tout'}|$jours|$tour';
    if (_cle == cle) return;
    _cle = cle;
    _charger(++_demande, ferme, jours);
  }

  Future<void> _charger(int demande, String? ferme, int jours) async {
    final fin = aujourdhui().add(const Duration(days: 1));
    // jours − 1 : de « aujourd'hui moins 29 » à demain exclu, cela fait
    // bien 30 journées. Avant, « 30 jours » en comptait 31.
    final debut = aujourdhui().subtract(Duration(days: jours - 1));

    // Chaque lecture est isolée, comme partout ailleurs dans
    // l'application : un seul échec sur trois noircissait les trois
    // blocs et jetait les deux réponses déjà arrivées.
    Future<T?> lire<T>(Future<T> Function() quoi) async {
      try {
        return await quoi().timeout(const Duration(seconds: 25));
      } catch (e) {
        if (mounted && demande == _demande) {
          setState(() => _panne = panneDe(e));
        }
        return null;
      }
    }

    final r = await Future.wait<dynamic>([
      lire(() => Api.ponteEntre(debut: debut, fin: fin, fermeId: ferme)),
      lire(() => Api.ponteComparee(fermeId: ferme)),
      lire(() =>
          Api.pontePourBatiments(debut: debut, fin: fin, fermeId: ferme)),
    ]);
    if (!mounted || demande != _demande) return;
    setState(() {
      // On garde ce qu'on avait quand une branche n'a rien rendu : les
      // effacer avant de tenter la lecture privait l'utilisateur des
      // seuls chiffres qu'il avait.
      if (r[0] != null) _periode = r[0] as Ponte;
      if (r[1] != null) _ponte = r[1] as PonteComparee;
      if (r[2] != null) _parBatiment = r[2] as Map<String, Ponte>;
      if (r[0] != null && r[1] != null && r[2] != null) _panne = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    // jours − 1, la même borne que _charger : sinon on divisait 31
    // jours de dépenses par 30 jours d'œufs.
    final depuis = aujourdhui().subtract(Duration(days: _jours - 1));
    final portee = _ferme ?? (etat.estAdmin ? null : etat.maFermeId);
    _assurerPonte(portee, _jours, etat.tour);

    bool dansLaPeriode(DateTime? d) =>
        d != null && !d.isBefore(depuis);
    bool deLaFerme(String fermeId) => portee == null || fermeId == portee;

    // ── Les matières premières du calcul ──
    // Seules les saisies VALIDÉES comptent, comme pour les recettes et
    // les dépenses : sinon le coût par œuf se calculait sur des œufs que
    // le gérant n'avait pas encore reconnus.
    final prods = etat.productions
        .where((p) =>
            p.statut == Statut.valide &&
            deLaFerme(p.fermeId) &&
            dansLaPeriode(p.date))
        .toList();
    // Le compte de la base fait foi dès qu'il est arrivé.
    final oeufs = _periode?.oeufs ?? prods.fold<int>(0, (s, p) => s + p.oeufs);
    // Des saisies existent mais ne sont pas validées : « aucune
    // production » serait faux, et le gérant chercherait la panne.
    final enAttente = etat.productions
        .where((p) =>
            p.statut != Statut.valide &&
            deLaFerme(p.fermeId) &&
            dansLaPeriode(p.date))
        .length;

    final depensesPeriode = etat.depenses
        .where((d) =>
            d.statut == Statut.valide &&
            deLaFerme(d.fermeId) &&
            dansLaPeriode(d.date))
        .toList();
    final totalDepenses = depensesPeriode.fold<int>(0, (s, d) => s + d.montant);

    final recettesPeriode = etat.recettes
        .where((r) =>
            r.statut == Statut.valide &&
            deLaFerme(r.fermeId) &&
            dansLaPeriode(r.date))
        .toList();
    final totalRecettes = recettesPeriode.fold<int>(0, (s, r) => s + r.montant);

    final batiments =
        etat.batiments.where((b) => deLaFerme(b.fermeId)).toList();
    // Les poules VIVANTES, pas celles mises en place : une bande qui a
    // perdu 500 sujets sur 2 000 voyait son taux de ponte sous-estimé
    // d'un tiers, et paraissait mauvaise alors qu'elle pondait bien.
    final poules =
        batiments.fold<int>(0, (s, b) => s + etat.effectifVivant(b));

    // ── Les indicateurs ──
    final joursAvecSaisie = prods
        .map((p) => iso(p.date ?? aujourdhui()))
        .toSet()
        .length;
    // null tant que la base n'a pas répondu : on n'invente pas un taux.
    final tauxPonte = _periode?.taux;
    final coutParOeuf = oeufs > 0 ? totalDepenses / oeufs : 0.0;
    final revenuParOeuf = oeufs > 0 ? totalRecettes / oeufs : 0.0;
    final margeParOeuf = revenuParOeuf - coutParOeuf;

    // Aliment acheté sur la période, en kilos.
    final kilosAliment = depensesPeriode
        .where((d) => d.categorie == 'aliment' && d.unite.toLowerCase().startsWith('kg'))
        .fold<double>(0, (s, d) => s + d.quantite);
    final plateaux = oeufs / oeufsParAlveole;
    final indiceConsommation =
        plateaux > 0 && kilosAliment > 0 ? kilosAliment / plateaux : 0.0;

    // Combien de jours d'aliment reste-t-il ?
    final stockAliment = etat.stocks
        .where((s) =>
            deLaFerme(s.fermeId) && s.nom.toLowerCase().contains('aliment'))
        .fold<double>(0, (s, x) => s + x.quantite);
    final consoJour =
        joursAvecSaisie > 0 && kilosAliment > 0 ? kilosAliment / _jours : 0.0;
    final joursRestants =
        consoJour > 0 ? (stockAliment / consoJour).floor() : -1;

    return RefreshIndicator(
      // Le tour de lecture change à la fin du rafraîchissement,
      // donc les pourcentages se redemandent tout seuls.
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _filtres(context, etat),
          const SizedBox(height: 16),

          // On n'annonce « aucune production » qu'une fois les chiffres
          // de la base arrivés : sinon, à chaque changement de ferme,
          // tout l'écran s'effondrait sur cette phrase avant de se
          // reconstruire une seconde plus tard.
          if (oeufs == 0 && _periode != null)
            Bloc(
                enfant: Vide(
                    enAttente > 0
                        ? '$enAttente journée${enAttente > 1 ? 's' : ''} de '
                            'ramassage ${enAttente > 1 ? 'attendent' : 'attend'} '
                            'la validation.\nElles ne comptent pas encore dans '
                            'les indicateurs.'
                        : 'Aucune production sur les $_jours derniers jours.\n'
                            'Les indicateurs apparaîtront dès les premières '
                            'saisies.',
                    icone: enAttente > 0
                        ? Icons.pending_actions_outlined
                        : Icons.query_stats_outlined))
          else ...[
            _titre(context, 'Pourcentage de ponte', '📈'),
            _comparaison(context),
            const SizedBox(height: 18),
            _titre(context, 'Rendement du cheptel', '🐔'),
            GrilleChiffres([
              CarteChiffre(
                  libelle: 'Taux de ponte',
                  valeur: (_periode?.invraisemblable ?? false)
                      ? '?'
                      : pourcent(tauxPonte),
                  complement: tauxPonte == null
                      ? (_panne != null ? 'indisponible' : 'calcul en cours')
                      : '${_jugementPonte(tauxPonte)} · $_jours jours',
                  couleur: (_periode?.invraisemblable ?? false)
                      ? Palette.orFonce
                      : _teinteTaux(tauxPonte),
                  icone: Icons.egg_rounded),
              CarteChiffre(
                  libelle: 'Œufs par poule et par jour',
                  valeur: (_periode?.poulesJours ?? 0) > 0
                      ? (_periode!.oeufsMesures / _periode!.poulesJours)
                          .toStringAsFixed(2)
                      : '—',
                  complement: 'moyenne sur $_jours jours',
                  couleur: Palette.bleu,
                  icone: Icons.calculate_rounded),
              CarteChiffre(
                  libelle: 'Œufs produits',
                  valeur: nb(oeufs),
                  complement: '${nb(plateaux.round())} plateaux',
                  couleur: Palette.vertMoyen,
                  icone: Icons.inventory_rounded),
              CarteChiffre(
                  libelle: 'Cheptel',
                  valeur: nb(poules),
                  complement: batiments.length == 1
                      ? 'un bâtiment'
                      : '${batiments.length} bâtiments',
                  couleur: Palette.gris,
                  icone: Icons.warehouse_rounded),
            ]),

            const SizedBox(height: 6),
            _titre(context, 'Ce que coûte et rapporte un œuf', '💰'),
            Bloc(
              enfant: Column(children: [
                _ligneEconomie(context, 'Il coûte', coutParOeuf, Palette.rouge,
                    'toutes les dépenses validées divisées par les œufs produits'),
                const Divider(height: 22),
                _ligneEconomie(context, 'Il rapporte', revenuParOeuf,
                    Palette.vert, 'toutes les recettes validées, même calcul'),
                const Divider(height: 22),
                _ligneEconomie(
                    context,
                    margeParOeuf >= 0 ? 'Vous gagnez' : 'Vous perdez',
                    margeParOeuf.abs(),
                    margeParOeuf >= 0 ? Palette.or : Palette.rouge,
                    'la différence entre les deux',
                    gras: true),
                if (margeParOeuf < 0) ...[
                  const SizedBox(height: 14),
                  const Bandeau(
                    titre: 'Chaque œuf produit vous coûte de l’argent',
                    texte:
                        'Soit les dépenses de la période comprennent un gros '
                        'achat exceptionnel (construction, cheptel), soit le '
                        'prix de vente est trop bas. Regardez la répartition '
                        'des dépenses juste en dessous.',
                    couleur: Palette.rouge,
                    icone: Icons.warning_amber_rounded,
                  ),
                ],
              ]),
            ),

            const SizedBox(height: 6),
            _titre(context, 'L’aliment', '🌽'),
            Bloc(
              enfant: Column(children: [
                if (indiceConsommation > 0)
                  _ligneIndicateur(
                    context,
                    'Indice de consommation',
                    '${indiceConsommation.toStringAsFixed(2)} kg',
                    'd’aliment par plateau de 30 œufs',
                    indiceConsommation <= 2.2
                        ? Palette.vert
                        : (indiceConsommation <= 2.8
                            ? Palette.orFonce
                            : Palette.rouge),
                  )
                else
                  _sansDonnee(context,
                      'Indice de consommation',
                      'Saisissez vos achats d’aliment en kilos (catégorie '
                          'Alimentation, unité « kg ») pour qu’il soit calculé.'),
                const Divider(height: 22),
                if (joursRestants >= 0)
                  _ligneIndicateur(
                    context,
                    'Aliment restant',
                    joursRestants > 60 ? 'plus de 60 jours' : '$joursRestants jours',
                    'au rythme de consommation des $_jours derniers jours',
                    joursRestants >= 14
                        ? Palette.vert
                        : (joursRestants >= 7
                            ? Palette.orFonce
                            : Palette.rouge),
                  )
                else
                  _sansDonnee(context, 'Aliment restant',
                      'Il faut un stock « Aliment » et des achats en kilos pour l’estimer.'),
              ]),
            ),

            const SizedBox(height: 6),
            _titre(context, 'Classement des bâtiments', '🏗️'),
            _classement(context, etat, batiments),

            const SizedBox(height: 6),
            _titre(context, 'Où part l’argent', '📊'),
            Bloc(
              enfant: AnneauCategories([
                for (final c in categoriesDepense)
                  (
                    libelle: c.libelle,
                    montant: depensesPeriode
                        .where((d) => d.categorie == c.cle)
                        .fold<int>(0, (s, d) => s + d.montant),
                    couleur: c.couleur,
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  /// Les mêmes seuils que partout ailleurs : 80 et 65. Avant, 68 % était
  /// rouge sur un écran et orange sur l'autre.
  static Color _teinteTaux(double? t) => t == null
      ? Palette.gris
      : (t >= 80 ? Palette.vert : (t >= 65 ? Palette.orFonce : Palette.rouge));

  String _jugementPonte(double t) {
    if (t > 105) return 'chiffre à vérifier';
    if (t >= 85) return 'excellent';
    if (t >= 75) return 'correct';
    if (t >= 60) return 'faible';
    return 'préoccupant';
  }

  /// Ce qu'on montre pendant que la base calcule — et ce qu'on montre
  /// quand elle n'a pas répondu, plutôt qu'un sablier sans fin.
  Widget _attente(BuildContext context) {
    if (_panne != null) {
      return Row(children: [
        Icon(
            _panne == Panne.reseau
                ? Icons.wifi_off_rounded
                : Icons.build_outlined,
            size: 18,
            color: Theme.of(context).hintColor),
        const SizedBox(width: 11),
        Expanded(
          child: Text(direPanne(_panne!),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }

  /// Le pourcentage de ponte de l'ensemble, et ce qu'il valait avant.
  ///
  /// Calculé par la BASE : le téléphone ne connaît qu'une partie des
  /// mortalités et des productions, et le chiffre différait alors
  /// entre le gérant et l'administrateur. Voir sql/17_idiama_ponte.sql.
  Widget _comparaison(BuildContext context) {
    final p = _ponte;
    if (p == null) return Bloc(enfant: _attente(context));
    return Bloc(
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ligne(context, 'Aujourd’hui', p.jour, p.jourAvant, 'hier'),
        // Les 7 derniers jours glissants, et non la semaine du
        // calendrier : le lundi matin, « cette semaine » ne contenait
        // qu'une matinée et l'écran annonçait une chute de trente
        // points, en rouge, sur un troupeau qui n'avait rien changé.
        _ligne(context, '7 derniers jours', p.septJours, p.septJoursAvant,
            'les 7 jours d’avant'),
        _ligne(context, 'Ce mois', p.mois, p.moisAvant, 'le mois passé'),
        const SizedBox(height: 6),
        Text(
            'Œufs ramassés rapportés aux poules vivantes de chaque jour, '
            'toutes bandes confondues — la mortalité déclarée est déduite. '
            'Ces trois lignes ne suivent pas la période choisie en haut : '
            'ce sont le jour, la semaine et le mois.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _ligne(BuildContext context, String quand, Ponte maintenant,
      Ponte avant, String contre) {
    final points = PonteComparee.ecart(maintenant, avant);
    final couleur = points == null || points.abs() < 0.5
        ? Palette.gris
        : (points >= 0.5
            ? Palette.vert
            : (points > -2 ? Palette.orFonce : Palette.rouge));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 104,
          child: Text(quand, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
            maintenant.invraisemblable ? '?' : pourcent(maintenant.taux),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              maintenant.invraisemblable
                  ? 'plus d’un œuf par poule : une saisie est à vérifier'
                  : (points == null
                      ? PonteComparee.direPourquoiRien(
                          maintenant, avant, contre)
                      : '${PonteComparee.direEcart(points)} contre $contre'),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: maintenant.invraisemblable
                      ? Palette.orFonce
                      : couleur)),
        ),
      ]),
    );
  }
  Widget _titre(BuildContext context, String texte, String emoji) =>
      TitreSection(texte, emoji: emoji);

  Widget _ligneEconomie(BuildContext context, String libelle, double valeur,
      Color couleur, String explication,
      {bool gras = false}) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle,
                style: TextStyle(
                    fontSize: gras ? 15 : 14,
                    fontWeight: gras ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(height: 2),
            Text(explication,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text('${valeur.toStringAsFixed(0)} GNF',
          style: TextStyle(
              fontSize: gras ? 21 : 18,
              fontWeight: FontWeight.w800,
              color: couleur)),
    ]);
  }

  Widget _ligneIndicateur(BuildContext context, String libelle, String valeur,
      String explication, Color couleur) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(explication, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text(valeur,
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: couleur)),
    ]);
  }

  Widget _sansDonnee(BuildContext context, String libelle, String pourquoi) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.help_outline_rounded,
          size: 18, color: Theme.of(context).hintColor),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(libelle,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(pourquoi, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ]);
  }

  /// Le classement des bâtiments, du meilleur taux au moins bon.
  ///
  /// Les taux viennent de la base : le téléphone divisait les œufs par
  /// l'effectif de DÉPART et comptait les saisies pas encore validées,
  /// ce qui sous-estimait les bandes ayant perdu des sujets et faisait
  /// remonter celles dont la saisie du jour n'était pas reconnue.
  Widget _classement(
      BuildContext context, Etat etat, List<Batiment> batiments) {
    if (batiments.isEmpty) {
      return const Bloc(
          enfant: Vide('Aucun bâtiment', icone: Icons.warehouse_outlined));
    }
    final par = _parBatiment;
    if (par == null) return Bloc(enfant: _attente(context));

    // Un bâtiment sans aucune saisie n'a pas un taux de zéro : il n'a
    // pas de taux. Il passe en dernier et le dit, au lieu de passer
    // pour le plus mauvais élevage de la ferme.
    final lignes =
        <({Batiment b, int oeufs, int jours, bool suspect, double? taux})>[];
    for (final b in batiments) {
      final p = par[b.id];
      lignes.add((
        b: b,
        oeufs: p?.oeufs ?? 0,
        jours: p?.jours ?? 0,
        suspect: p?.invraisemblable == true,
        taux: p?.invraisemblable == true ? null : p?.taux,
      ));
    }
    // Le mieux rempli donne la mesure : en dessous de la moitié de ses
    // journées, un bâtiment n'est pas comparable et ne se classe pas.
    final plein = lignes.fold<int>(0, (m, l) => l.jours > m ? l.jours : m);
    bool assez(int jours) => jours > 0 && jours * 2 >= plein;
    lignes.sort((a, b) {
      final pa = a.taux != null && assez(a.jours);
      final pb = b.taux != null && assez(b.jours);
      if (pa != pb) return pb ? 1 : -1;
      return (b.taux ?? -1).compareTo(a.taux ?? -1);
    });
    final mesures =
        lignes.where((l) => l.taux != null && assez(l.jours)).toList();
    final meilleur = mesures.isEmpty ? 0.0 : mesures.first.taux!;


    return Bloc(
      enfant: Column(children: [
        for (var i = 0; i < lignes.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: (i == 0 && lignes[i].taux != null
                        ? Palette.or
                        : Palette.gris)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: i == 0 && lignes[i].taux != null
                          ? Palette.orFonce
                          : Palette.gris)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lignes[i].b.nom,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(
                      lignes[i].suspect
                          ? '${nb(lignes[i].oeufs)} œufs · plus d’un œuf par '
                              'poule : vérifiez les alvéoles saisies'
                          : lignes[i].taux != null && !assez(lignes[i].jours)
                          ? '${nb(lignes[i].oeufs)} œufs · trop peu de '
                              'journées pour comparer'
                          : lignes[i].taux == null
                          ? (lignes[i].oeufs > 0
                              // Des œufs mais pas de taux : personne
                              // n'a compté les poules. « Aucune
                              // saisie » était un mensonge.
                              ? '${nb(lignes[i].oeufs)} œufs · cheptel inconnu : '
                                  'effectif ou mortalité à vérifier'
                              : 'aucune saisie sur la période')
                          : '${nb(etat.effectifVivant(lignes[i].b))} poules vivantes · ${nb(lignes[i].oeufs)} œufs'
                            '${etat.estAdmin ? ' · ${etat.nomFerme(lignes[i].b.fermeId)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
                lignes[i].taux == null
                    ? '—'
                    : pourcent(lignes[i].taux, decimales: 0),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _teinteTaux(lignes[i].taux))),
          ]),
          const SizedBox(height: 7),
          Jauge(
            meilleur > 0 && lignes[i].taux != null
                ? (lignes[i].taux! / meilleur * 100).round()
                : 0,
            couleur: _teinteTaux(lignes[i].taux),
          ),
        ],
        // Au moins quatre journées de ramassage de chaque côté : un
        // bâtiment avec une seule saisie partielle passait pour un
        // mauvais élevage.
        if (mesures.length > 1 &&
            mesures.first.jours >= 4 &&
            mesures.last.jours >= 4 &&
            mesures.first.taux! - mesures.last.taux! > 15) ...[
          const SizedBox(height: 16),
          Bandeau(
            titre: 'Écart important entre bâtiments',
            texte:
                '${mesures.first.b.nom} pond ${(mesures.first.taux! - mesures.last.taux!).round()} points '
                'de plus que ${mesures.last.b.nom}. Même aliment, même âge ? '
                'Regardez la ventilation, l’abreuvement et l’état du dernier.',
            couleur: Palette.orFonce,
            icone: Icons.compare_arrows_rounded,
          ),
        ],
      ]),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final j in [7, 30, 90]) ...[
          ChoiceChip(
            selected: _jours == j,
            label: Text('$j jours'),
            onSelected: (_) => setState(() => _jours = j),
          ),
          const SizedBox(width: 8),
        ],
        if (etat.estAdmin)
          PopupMenuButton<String?>(
            onSelected: (v) => setState(() => _ferme = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Toutes les fermes')),
              for (final f in etat.fermes)
                PopupMenuItem(value: f.id, child: Text(f.nom)),
            ],
            child: Chip(
              avatar: const Icon(Icons.holiday_village_outlined, size: 17),
              label: Text(
                  _ferme == null ? 'Toutes les fermes' : etat.nomFerme(_ferme)),
            ),
          ),
      ]),
    );
  }
}
