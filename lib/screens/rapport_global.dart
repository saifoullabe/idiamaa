import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../widgets/communs.dart';
import '../widgets/graphiques.dart';

/// La synthèse financière de toutes les fermes, ferme par ferme
/// puis catégorie par catégorie.
class EcranRapportGlobal extends StatefulWidget {
  const EcranRapportGlobal({super.key});

  @override
  State<EcranRapportGlobal> createState() => _EcranRapportGlobalState();
}

class _EcranRapportGlobalState extends State<EcranRapportGlobal> {
  DateTime? _mois;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final lignes = [
      for (final f in etat.fermes)
        (
          nom: f.nom,
          recettes: etat.totalRecettes(fermeId: f.id, mois: _mois),
          depenses: etat.totalDepenses(fermeId: f.id, mois: _mois),
          depots: etat.totalDepotsRecus(fermeId: f.id, mois: _mois),
        ),
    ];

    final totalRecettes = lignes.fold<int>(0, (s, l) => s + l.recettes);
    final totalDepenses = lignes.fold<int>(0, (s, l) => s + l.depenses);
    final totalDepots = lignes.fold<int>(0, (s, l) => s + l.depots);
    final benefice = totalRecettes - totalDepenses;

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _filtreMois(context),
          const SizedBox(height: 14),
          GrilleChiffres([
            CarteChiffre(
                libelle: 'Recettes',
                valeur: gnfCourt(totalRecettes),
                couleur: Palette.vert,
                icone: Icons.trending_up_rounded),
            CarteChiffre(
                libelle: 'Dépenses',
                valeur: gnfCourt(totalDepenses),
                couleur: Palette.rouge,
                icone: Icons.trending_down_rounded),
            CarteChiffre(
                libelle: 'Bénéfice',
                valeur: gnfCourt(benefice),
                complement: totalRecettes > 0
                    ? 'marge ${(benefice / totalRecettes * 100).round()} %'
                    : null,
                couleur: benefice >= 0 ? Palette.or : Palette.rouge,
                icone: Icons.savings_rounded),
            CarteChiffre(
                libelle: 'Dépôts versés',
                valeur: gnfCourt(totalDepots),
                couleur: Palette.bleu,
                icone: Icons.account_balance_rounded),
          ]),
          const SizedBox(height: 16),
          Bloc(
            enfant: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Évolution',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 16),
                  BarresMensuelles(etat.serieMensuelle()),
                ]),
          ),
          const TitreSection('Résultat par ferme', emoji: '🏚️'),
          Bloc(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            enfant: lignes.isEmpty
                ? const Vide('Aucune ferme',
                    icone: Icons.holiday_village_outlined)
                : Column(children: [
                    for (final l in lignes) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              child: Text(l.nom,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                            ),
                            Text(
                                gnfCourt(l.recettes - l.depenses),
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: l.recettes - l.depenses >= 0
                                        ? Palette.vert
                                        : Palette.rouge)),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _cellule(context, 'Recettes', l.recettes,
                                Palette.vert),
                            _cellule(context, 'Dépenses', l.depenses,
                                Palette.rouge),
                            _cellule(
                                context, 'Dépôts', l.depots, Palette.bleu),
                            Expanded(
                              child: Column(children: [
                                Text('Marge',
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                                const SizedBox(height: 3),
                                Text(
                                    l.recettes > 0
                                        ? '${((l.recettes - l.depenses) / l.recettes * 100).round()} %'
                                        : '—',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800)),
                              ]),
                            ),
                          ]),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(children: [
                        Expanded(
                          child: Text('TOTAL GÉNÉRAL',
                              style: Theme.of(context).textTheme.labelMedium),
                        ),
                        Text(gnf(benefice),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: benefice >= 0
                                    ? Palette.vert
                                    : Palette.rouge)),
                      ]),
                    ),
                  ]),
          ),
          const TitreSection('Dépenses consolidées', emoji: '📊'),
          Bloc(
            enfant: Column(children: [
              AnneauCategories([
                for (final c in categoriesDepense)
                  (
                    libelle: c.libelle,
                    montant: etat.totalDepenses(mois: _mois, categorie: c.cle),
                    couleur: c.couleur,
                  ),
              ]),
              const Divider(height: 26),
              for (final c in categoriesDepense)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Text(c.emoji),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(c.libelle,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                        '-${gnf(etat.totalDepenses(mois: _mois, categorie: c.cle))}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: c.couleur)),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _cellule(BuildContext context, String libelle, int valeur, Color c) =>
      Expanded(
        child: Column(children: [
          Text(libelle, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          FittedBox(
            child: Text(gnfCourt(valeur),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: c)),
          ),
        ]),
      );

  Widget _filtreMois(BuildContext context) {
    final maintenant = DateTime.now();
    return Row(children: [
      PopupMenuButton<DateTime?>(
        onSelected: (v) => setState(() => _mois = v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: null, child: Text('Depuis le début')),
          for (var i = 0; i < 12; i++)
            PopupMenuItem(
              value: DateTime(maintenant.year, maintenant.month - i),
              child: Text(
                  moisAnnee(DateTime(maintenant.year, maintenant.month - i))),
            ),
        ],
        child: Chip(
          avatar: const Icon(Icons.calendar_month_outlined, size: 17),
          label: Text(_mois == null ? 'Depuis le début' : moisAnnee(_mois)),
        ),
      ),
      const Spacer(),
      Text('Chiffres validés uniquement',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
