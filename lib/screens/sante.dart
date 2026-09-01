import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/elevage.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/photos.dart';
import 'formulaires.dart';

/// La santé du cheptel : combien de poules vivantes, combien de morts,
/// et où en est le calendrier vaccinal — tout calculé depuis le jour
/// d'arrivage du lot.
class EcranSante extends StatefulWidget {
  const EcranSante({super.key});

  @override
  State<EcranSante> createState() => _EcranSanteState();
}

class _EcranSanteState extends State<EcranSante> {
  String? _batimentOuvert;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final batiments = etat.estAdmin
        ? etat.batiments
        : etat.batimentsDe(etat.maFermeId);

    final effectifDepart =
        batiments.fold<int>(0, (s, b) => s + b.nbPoules);
    final vivantes =
        batiments.fold<int>(0, (s, b) => s + etat.effectifVivant(b));
    final mortsTotal = effectifDepart - vivantes;
    final mortsAujourdhui = batiments.fold<int>(
        0, (s, b) => s + etat.mortsDuJour(b.id, aujourdhui()));

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          GrilleChiffres([
            CarteChiffre(
                libelle: 'Poules vivantes',
                valeur: nb(vivantes),
                complement: 'sur ${nb(effectifDepart)} mises en place',
                couleur: Palette.vert,
                icone: Icons.groups_rounded),
            CarteChiffre(
                libelle: 'Mortalité cumulée',
                valeur: effectifDepart > 0
                    ? '${(mortsTotal / effectifDepart * 100).toStringAsFixed(1)} %'
                    : '—',
                complement: '${nb(mortsTotal)} poules',
                couleur: Palette.rouge,
                icone: Icons.trending_down_rounded),
            CarteChiffre(
                libelle: 'Morts aujourd’hui',
                valeur: '$mortsAujourdhui',
                couleur: mortsAujourdhui == 0
                    ? Palette.vert
                    : (mortsAujourdhui > 5 ? Palette.rouge : Palette.orFonce),
                icone: Icons.today_rounded),
            CarteChiffre(
                libelle: 'Bâtiments suivis',
                valeur: '${batiments.where((b) => b.ageConnu).length}'
                    '/${batiments.length}',
                complement: 'avec jour d’arrivage',
                couleur: Palette.bleu,
                icone: Icons.warehouse_rounded),
          ]),
          const SizedBox(height: 18),
          if (batiments.isEmpty)
            const Bloc(
                enfant: Vide('Aucun bâtiment',
                    icone: Icons.warehouse_outlined))
          else
            for (final b in batiments) _carteBatiment(context, etat, b),
          const SizedBox(height: 18),
          _avertissement(context),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // UN BÂTIMENT
  // ══════════════════════════════════════════════════════════════════
  Widget _carteBatiment(BuildContext context, Etat etat, Batiment b) {
    final vivantes = etat.effectifVivant(b);
    final taux = etat.tauxMortalite(b);
    final ouvert = _batimentOuvert == b.id;
    final semaines = b.ageSemaines;
    final attendu = b.ageConnu ? ponteAttendue(semaines) : 0;

    // Le taux de ponte réel des 7 derniers jours, sur l'effectif VIVANT.
    final depuis = aujourdhui().subtract(const Duration(days: 7));
    final prods = etat.productions.where(
        (p) => p.batimentId == b.id && p.date != null && !p.date!.isBefore(depuis));
    final joursSaisis = prods.map((p) => iso(p.date!)).toSet().length;
    final oeufs = prods.fold<int>(0, (s, p) => s + p.oeufs);
    final ponteReelle = (vivantes > 0 && joursSaisis > 0)
        ? oeufs / (vivantes * joursSaisis) * 100
        : -1.0;

    final ecart = (b.ageConnu && ponteReelle >= 0 && attendu > 0)
        ? ponteReelle - attendu
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // ── En-tête ──
          InkWell(
            onTap: () =>
                setState(() => _batimentOuvert = ouvert ? null : b.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.nom,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                          b.ageConnu
                              ? '$semaines semaines · ${phaseDuLot(semaines)}'
                                  '${etat.estAdmin ? ' · ${etat.nomFerme(b.fermeId)}' : ''}'
                              : 'Jour d’arrivage non renseigné',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(ouvert
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
              ]),
            ),
          ),

          // ── Les trois chiffres ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(children: [
              _tuile(context, 'Vivantes', nb(vivantes),
                  'sur ${nb(b.nbPoules)}', Palette.vert),
              _tuile(
                  context,
                  'Mortalité',
                  '${taux.toStringAsFixed(1)} %',
                  b.ageConnu
                      ? 'normal < ${mortaliteAcceptable(semaines).toStringAsFixed(1)} %'
                      : 'cumulée',
                  taux <= mortaliteAcceptable(b.ageConnu ? semaines : 0)
                      ? Palette.vert
                      : Palette.rouge),
              _tuile(
                  context,
                  'Ponte 7 j',
                  ponteReelle < 0 ? '—' : '${ponteReelle.toStringAsFixed(0)} %',
                  b.ageConnu ? 'attendu $attendu %' : 'âge inconnu',
                  ecart == null
                      ? Palette.gris
                      : (ecart >= -5
                          ? Palette.vert
                          : (ecart >= -15 ? Palette.orFonce : Palette.rouge))),
            ]),
          ),

          // ── Le verdict ──
          if (ecart != null && ecart < -8)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: 'Ponte inférieure au standard de son âge',
                texte:
                    'À $semaines semaines, un lot en bonne santé pond autour de '
                    '$attendu %. Celui-ci est à ${ponteReelle.toStringAsFixed(0)} %, '
                    'soit ${ecart.abs().toStringAsFixed(0)} points de moins. '
                    'Regardez l’aliment, l’eau, la chaleur et les vaccins.',
                couleur: ecart < -20 ? Palette.rouge : Palette.orFonce,
                icone: Icons.trending_down_rounded,
              ),
            ),
          if (!b.ageConnu)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: 'Renseignez le jour d’arrivage',
                texte:
                    'Sans lui, pas d’âge, donc pas de calendrier vaccinal ni de '
                    'comparaison au standard. Modifiez le bâtiment depuis la '
                    'fiche de la ferme.',
                couleur: Palette.orFonce,
                icone: Icons.event_busy_outlined,
              ),
            ),

          // ── Boutons ──
          const Divider(height: 1),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.rouge,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const RoundedRectangleBorder()),
                onPressed: () => formulaireMortalite(context, b),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                label: const Text('Déclarer des morts'),
              ),
            ),
            Container(
                width: 1, height: 28, color: Theme.of(context).dividerColor),
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.vertMoyen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const RoundedRectangleBorder()),
                onPressed: () =>
                    setState(() => _batimentOuvert = ouvert ? null : b.id),
                icon: const Icon(Icons.vaccines_outlined, size: 18),
                label: const Text('Calendrier'),
              ),
            ),
          ]),

          // ── Le calendrier du lot ──
          if (ouvert) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: _calendrier(context, etat, b),
            ),
            _historiqueMortalite(context, etat, b),
          ],
        ]),
      ),
    );
  }

  Widget _tuile(BuildContext context, String libelle, String valeur,
          String sous, Color c) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(children: [
            Text(libelle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(valeur,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: c)),
            ),
            const SizedBox(height: 2),
            Text(sous,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );

  // ══════════════════════════════════════════════════════════════════
  // LE CALENDRIER VACCINAL, EN VRAIES DATES
  // ══════════════════════════════════════════════════════════════════
  Widget _calendrier(BuildContext context, Etat etat, Batiment b) {
    if (!b.ageConnu) {
      return const Vide(
          'Le calendrier apparaîtra dès que le jour d’arrivage sera renseigné.',
          icone: Icons.event_busy_outlined);
    }

    final age = b.ageJours;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.vaccines_rounded, size: 17, color: Palette.vert),
        const SizedBox(width: 8),
        Text('Calendrier du lot',
            style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        Text('arrivé le ${jour(b.dateMiseEnPlace)}',
            style: Theme.of(context).textTheme.labelSmall),
      ]),
      const SizedBox(height: 12),
      for (final e in programmeVaccinal) _etape(context, etat, b, e, age),
      const SizedBox(height: 6),
      _jalons(context, b),
    ]);
  }

  Widget _etape(BuildContext context, Etat etat, Batiment b, EtapeVaccin e,
      int age) {
    final fait = etat.vaccinFait(b.id, e.vaccin, e.jour);
    final datePrevue = b.dateAuJour(e.jour);
    final joursRestants = e.jour - age;

    final Color couleur;
    final IconData icone;
    final String statut;
    if (fait != null) {
      couleur = Palette.vert;
      icone = Icons.check_circle_rounded;
      statut = 'Fait le ${jour(fait.dateFaite)}';
    } else if (joursRestants < -7) {
      couleur = Palette.rouge;
      icone = Icons.error_rounded;
      statut = 'En retard de ${-joursRestants} jours';
    } else if (joursRestants <= 0) {
      couleur = Palette.orFonce;
      icone = Icons.notifications_active_rounded;
      statut = joursRestants == 0 ? 'À faire aujourd’hui' : 'À faire';
    } else if (joursRestants <= 7) {
      couleur = Palette.bleu;
      icone = Icons.schedule_rounded;
      statut = 'Dans $joursRestants jour(s)';
    } else {
      couleur = Palette.gris;
      icone = Icons.circle_outlined;
      statut = 'Plus tard';
    }

    final aVenirLointain = fait == null && joursRestants > 30;

    return Opacity(
      opacity: aVenirLointain ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: fait != null
            ? null
            : () => formulaireVaccination(context, b, e),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, size: 19, color: couleur),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.vaccin,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      'J${e.jour} · ${jour(datePrevue)} · ${e.voie}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (!aVenirLointain) ...[
                    const SizedBox(height: 2),
                    Text('Contre ${e.contre}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Etiquette(statut, couleur: couleur),
              if (fait == null && joursRestants <= 7)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Appuyer pour cocher',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Les grandes dates de la vie du lot, en plus des vaccins.
  Widget _jalons(BuildContext context, Batiment b) {
    final jalons = [
      (126, 'Entrée en ponte attendue', '18 semaines'),
      (182, 'Pic de ponte', '26 semaines'),
      (560, 'Fin de cycle / réforme', '80 semaines'),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Palette.or.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LES GRANDES DATES DE CE LOT',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        for (final (j, quoi, quand) in jalons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(
                  b.ageJours >= j
                      ? Icons.check_circle_outline_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: b.ageJours >= j ? Palette.vert : Palette.gris),
              const SizedBox(width: 9),
              Expanded(
                child: Text(quoi,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Text('${jour(b.dateAuJour(j))}  ($quand)',
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // L'HISTORIQUE DES MORTS
  // ══════════════════════════════════════════════════════════════════
  Widget _historiqueMortalite(BuildContext context, Etat etat, Batiment b) {
    final lignes = etat.mortalites
        .where((m) => m.batimentId == b.id && m.nombre > 0)
        .toList()
      ..sort((a, c) => (c.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));

    if (lignes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Palette.vert.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text('Aucune mortalité déclarée sur ce bâtiment.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DERNIÈRES DÉCLARATIONS',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        for (final m in lignes.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emojiCause(m.cause),
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.nombre} poule(s) · ${jour(m.date)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                            '${m.cause} · ${etat.nomPersonne(m.auteurId)}'
                            '${m.note.isEmpty ? '' : ' — ${m.note}'}',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (m.photos.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          GaleriePhotos(m.photos, taille: 56),
                        ],
                      ],
                    ),
                  ),
                  if (etat.estAdmin || etat.estGerant)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _supprimer(context, etat, m),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: Theme.of(context).hintColor),
                    ),
                ]),
          ),
      ]),
    );
  }

  Future<void> _supprimer(
      BuildContext context, Etat etat, Mortalite m) async {
    final ok = await confirmer(context,
        titre: 'Supprimer cette déclaration ?',
        texte: '${m.nombre} poule(s) le ${jour(m.date)}. '
            'L’effectif vivant remontera d’autant.',
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerMortalite(m.id));
    if (context.mounted) {
      message(context, e ?? 'Déclaration supprimée', erreur: e != null);
    }
  }

  Widget _avertissement(BuildContext context) => Bloc(
        padding: const EdgeInsets.all(15),
        enfant: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.medical_information_outlined,
              size: 19, color: Theme.of(context).hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le calendrier vaccinal et les taux de ponte affichés sont des '
              'repères courants pour des pondeuses en climat tropical. Ils '
              'servent à vous alerter, pas à remplacer votre vétérinaire : '
              'le programme réel dépend de la souche, du fournisseur de '
              'vaccins et des maladies présentes autour de vos fermes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
      );
}
