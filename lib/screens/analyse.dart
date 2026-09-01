import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final depuis = aujourdhui().subtract(Duration(days: _jours));
    final portee = _ferme ?? (etat.estAdmin ? null : etat.maFermeId);

    bool dansLaPeriode(DateTime? d) =>
        d != null && !d.isBefore(depuis);
    bool deLaFerme(String fermeId) => portee == null || fermeId == portee;

    // ── Les matières premières du calcul ──
    final prods = etat.productions
        .where((p) => deLaFerme(p.fermeId) && dansLaPeriode(p.date))
        .toList();
    final oeufs = prods.fold<int>(0, (s, p) => s + p.oeufs);

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
    final poules = batiments.fold<int>(0, (s, b) => s + b.nbPoules);

    // ── Les indicateurs ──
    final joursAvecSaisie = prods
        .map((p) => iso(p.date ?? aujourdhui()))
        .toSet()
        .length;
    final tauxPonte = (poules > 0 && joursAvecSaisie > 0)
        ? (oeufs / (poules * joursAvecSaisie) * 100)
        : 0.0;
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
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _filtres(context, etat),
          const SizedBox(height: 16),

          if (oeufs == 0)
            Bloc(
                enfant: Vide(
                    'Aucune production sur les $_jours derniers jours.\n'
                    'Les indicateurs apparaîtront dès les premières saisies.',
                    icone: Icons.query_stats_outlined))
          else ...[
            _titre(context, 'Rendement du cheptel', '🐔'),
            GrilleChiffres([
              CarteChiffre(
                  libelle: 'Taux de ponte',
                  valeur: '${tauxPonte.toStringAsFixed(1)} %',
                  complement: _jugementPonte(tauxPonte),
                  couleur: tauxPonte >= 80
                      ? Palette.vert
                      : (tauxPonte >= 65 ? Palette.orFonce : Palette.rouge),
                  icone: Icons.egg_rounded),
              CarteChiffre(
                  libelle: 'Œufs par poule',
                  valeur: poules > 0
                      ? (oeufs / poules).toStringAsFixed(1)
                      : '—',
                  complement: 'sur $_jours jours',
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
                  complement: '${batiments.length} bâtiment(s)',
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
                          'Alimentation, unité « kg ») pour que je puisse le calculer.'),
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
            _classement(context, etat, batiments, depuis),

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

  String _jugementPonte(double t) {
    if (t >= 85) return 'excellent';
    if (t >= 75) return 'correct';
    if (t >= 60) return 'faible';
    return 'préoccupant';
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

  Widget _classement(BuildContext context, Etat etat, List<Batiment> batiments,
      DateTime depuis) {
    final lignes = <({Batiment b, int oeufs, double taux})>[];
    for (final b in batiments) {
      final p = etat.productions.where((x) =>
          x.batimentId == b.id &&
          x.date != null &&
          !x.date!.isBefore(depuis));
      final o = p.fold<int>(0, (s, x) => s + x.oeufs);
      final jours = p.map((x) => iso(x.date!)).toSet().length;
      final taux = (b.nbPoules > 0 && jours > 0)
          ? o / (b.nbPoules * jours) * 100
          : 0.0;
      lignes.add((b: b, oeufs: o, taux: taux));
    }
    lignes.sort((a, b) => b.taux.compareTo(a.taux));

    if (lignes.isEmpty) {
      return const Bloc(
          enfant: Vide('Aucun bâtiment', icone: Icons.warehouse_outlined));
    }

    final meilleur = lignes.first.taux;
    return Bloc(
      enfant: Column(children: [
        for (var i = 0; i < lignes.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: (i == 0 ? Palette.or : Palette.gris)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: i == 0 ? Palette.orFonce : Palette.gris)),
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
                      '${nb(lignes[i].b.nbPoules)} poules · '
                      '${nb(lignes[i].oeufs)} œufs'
                      '${etat.estAdmin ? ' · ${etat.nomFerme(lignes[i].b.fermeId)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text('${lignes[i].taux.toStringAsFixed(0)} %',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: lignes[i].taux >= 80
                        ? Palette.vert
                        : (lignes[i].taux >= 65
                            ? Palette.orFonce
                            : Palette.rouge))),
          ]),
          const SizedBox(height: 7),
          Jauge(
            meilleur > 0 ? (lignes[i].taux / meilleur * 100).round() : 0,
            couleur: lignes[i].taux >= 80
                ? Palette.vert
                : (lignes[i].taux >= 65 ? Palette.orFonce : Palette.rouge),
          ),
        ],
        if (lignes.length > 1 && lignes.first.taux - lignes.last.taux > 15) ...[
          const SizedBox(height: 16),
          Bandeau(
            titre: 'Écart important entre bâtiments',
            texte:
                '${lignes.first.b.nom} pond ${(lignes.first.taux - lignes.last.taux).round()} points '
                'de plus que ${lignes.last.b.nom}. Même aliment, même âge ? '
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
