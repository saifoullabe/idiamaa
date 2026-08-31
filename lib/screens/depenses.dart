import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/graphiques.dart';
import 'formulaires.dart';

/// Les dépenses rangées par catégorie puis par article, comme dans
/// le cahier de la ferme : on voit tout de suite où part l'argent.
class EcranDepenses extends StatefulWidget {
  const EcranDepenses({super.key});

  @override
  State<EcranDepenses> createState() => _EcranDepensesState();
}

class _EcranDepensesState extends State<EcranDepenses> {
  String? _ferme;
  DateTime? _mois;
  bool _seulementMesSaisies = false;
  final Set<String> _ouvertes = {};

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final lignes = etat.depenses.where((d) {
      if (_ferme != null && d.fermeId != _ferme) return false;
      if (_seulementMesSaisies && d.auteurId != etat.moi!.id) return false;
      if (_mois != null &&
          (d.date == null ||
              d.date!.year != _mois!.year ||
              d.date!.month != _mois!.month)) return false;
      return true;
    }).toList();

    final grandTotal = lignes
        .where((d) => d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    final enAttente = lignes
        .where((d) => Statut.enAttente(d.statut))
        .fold<int>(0, (s, d) => s + d.montant);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _filtres(context, etat),
            const SizedBox(height: 14),
            GrilleChiffres([
              CarteChiffre(
                  libelle: 'Dépenses validées',
                  valeur: gnfCourt(grandTotal),
                  complement: '${lignes.where((d) => d.statut == Statut.valide).length} ligne(s)',
                  couleur: Palette.rouge,
                  icone: Icons.trending_down_rounded),
              CarteChiffre(
                  libelle: 'En attente',
                  valeur: gnfCourt(enAttente),
                  complement:
                      '${lignes.where((d) => Statut.enAttente(d.statut)).length} saisie(s)',
                  couleur: Palette.orFonce,
                  icone: Icons.hourglass_top_rounded),
            ], largeurMin: 150),
            const SizedBox(height: 16),
            if (grandTotal > 0)
              Bloc(
                enfant: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Où part l’argent',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 14),
                      AnneauCategories([
                        for (final c in categoriesDepense)
                          (
                            libelle: c.libelle,
                            montant: lignes
                                .where((d) =>
                                    d.categorie == c.cle &&
                                    d.statut == Statut.valide)
                                .fold<int>(0, (s, d) => s + d.montant),
                            couleur: c.couleur,
                          ),
                      ]),
                    ]),
              ),
            const SizedBox(height: 18),
            for (final c in categoriesDepense)
              _sectionCategorie(
                  context, etat, c, lignes.where((d) => d.categorie == c.cle).toList()),
            const SizedBox(height: 8),
            _recapitulatif(context, lignes, grandTotal),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Palette.rouge,
        foregroundColor: Colors.white,
        onPressed: () => formulaireDepense(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle dépense'),
      ),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
    final maintenant = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (etat.estAdmin) ...[
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
          const SizedBox(width: 8),
        ],
        if (etat.estFermier) ...[
          FilterChip(
            selected: _seulementMesSaisies,
            label: const Text('Mes dépenses'),
            avatar: const Icon(Icons.person_outline_rounded, size: 17),
            onSelected: (v) => setState(() => _seulementMesSaisies = v),
          ),
          const SizedBox(width: 8),
        ],
        PopupMenuButton<DateTime?>(
          onSelected: (v) => setState(() => _mois = v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: null, child: Text('Tous les mois')),
            for (var i = 0; i < 12; i++)
              PopupMenuItem(
                value: DateTime(maintenant.year, maintenant.month - i),
                child: Text(
                    moisAnnee(DateTime(maintenant.year, maintenant.month - i))),
              ),
          ],
          child: Chip(
            avatar: const Icon(Icons.calendar_month_outlined, size: 17),
            label: Text(_mois == null ? 'Tous les mois' : moisAnnee(_mois)),
          ),
        ),
        if (_ferme != null || _mois != null || _seulementMesSaisies) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Effacer'),
            onPressed: () => setState(() {
              _ferme = null;
              _mois = null;
              _seulementMesSaisies = false;
            }),
          ),
        ],
      ]),
    );
  }

  Widget _sectionCategorie(BuildContext context, Etat etat,
      CategorieDepense cat, List<Depense> lignes) {
    lignes.sort((a, b) =>
        (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    final total = lignes
        .where((d) => d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    final ouverte = _ouvertes.contains(cat.cle);

    // Regroupement par article, pour ne pas noyer les lignes.
    final parArticle = <String, List<Depense>>{};
    for (final d in lignes) {
      parArticle.putIfAbsent(d.article.isEmpty ? '—' : d.article, () => []).add(d);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          InkWell(
            onTap: () => setState(() =>
                ouverte ? _ouvertes.remove(cat.cle) : _ouvertes.add(cat.cle)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
              color: cat.couleur,
              child: Row(children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.libelle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800)),
                      Text('${lignes.length} ligne(s)',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11)),
                    ],
                  ),
                ),
                Text('-${gnfCourt(total)}',
                    style: const TextStyle(
                        color: Color(0xFFFDD835),
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Ajouter dans ${cat.libelle}',
                  onPressed: () =>
                      formulaireDepense(context, categorieDepart: cat.cle),
                  icon: const Icon(Icons.add_circle_outline_rounded,
                      color: Colors.white, size: 21),
                ),
                Icon(
                    ouverte
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.white),
              ]),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: ouverte
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: lignes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: Vide('Aucune dépense dans cette catégorie',
                        icone: Icons.inbox_rounded,
                        action: 'Ajouter',
                        auClic: () => formulaireDepense(context,
                            categorieDepart: cat.cle)),
                  )
                : Column(children: [
                    for (final entree in parArticle.entries)
                      _groupeArticle(context, etat, cat, entree.key,
                          entree.value),
                  ]),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }

  Widget _groupeArticle(BuildContext context, Etat etat, CategorieDepense cat,
      String article, List<Depense> lignes) {
    final total = lignes
        .where((d) => d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: cat.couleur.withValues(alpha: 0.10),
        child: Row(children: [
          Expanded(
            child: Text(article,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cat.couleur)),
          ),
          Text('-${gnf(total)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: cat.couleur)),
        ]),
      ),
      for (final d in lignes) _ligne(context, etat, d),
    ]);
  }

  Widget _ligne(BuildContext context, Etat etat, Depense d) {
    final peutSupprimer = etat.estAdmin ||
        etat.estGerant ||
        (d.auteurId == etat.moi!.id && Statut.enAttente(d.statut));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(jour(d.date),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 8),
                PuceStatut(d.statut, compact: true),
              ]),
              if (d.quantite > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                      '${nb(d.quantite)} ${d.unite}'
                      '${d.prixUnitaire > 0 ? ' × ${gnf(d.prixUnitaire)}' : ''}',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              if (etat.estAdmin)
                Text(
                    '${etat.nomFerme(d.fermeId)} · ${etat.nomPersonne(d.auteurId)}',
                    style: Theme.of(context).textTheme.bodySmall),
              if (d.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(d.description,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ),
              if (d.statut == Statut.rejete && d.motifRejet.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Rejetée : ${d.motifRejet}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: Palette.rouge,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        Montant(d.montant, negatif: true, taille: 14.5),
        if (peutSupprimer)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _supprimer(context, etat, d),
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: Theme.of(context).hintColor),
          )
        else
          const SizedBox(width: 8),
      ]),
    );
  }

  Widget _recapitulatif(
      BuildContext context, List<Depense> lignes, int grandTotal) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF071A07), Palette.vert],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('RÉCAPITULATIF',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in categoriesDepense)
              if (lignes
                      .where((d) =>
                          d.categorie == c.cle && d.statut == Statut.valide)
                      .fold<int>(0, (s, d) => s + d.montant) >
                  0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.libelle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10)),
                      Text(
                          '-${gnfCourt(lignes.where((d) => d.categorie == c.cle && d.statut == Statut.valide).fold<int>(0, (s, d) => s + d.montant))}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(color: Colors.white.withValues(alpha: 0.18)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text('GRAND TOTAL',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('-${gnf(grandTotal)}',
                style: const TextStyle(
                    color: Color(0xFFFDD835),
                    fontSize: 21,
                    fontWeight: FontWeight.w800)),
            Text('${lignes.length} dépense(s)',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 10.5)),
          ]),
        ]),
      ]),
    );
  }

  Future<void> _supprimer(BuildContext context, Etat etat, Depense d) async {
    final ok = await confirmer(context,
        titre: 'Supprimer cette dépense ?',
        texte: '${d.article} — ${gnf(d.montant)} du ${jour(d.date)}.',
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerDepense(d.id));
    if (context.mounted) {
      message(context, e ?? 'Dépense supprimée', erreur: e != null);
    }
  }
}
