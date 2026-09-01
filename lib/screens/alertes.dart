import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../widgets/communs.dart';

/// Le degré d'urgence d'une alerte — il décide de la couleur et de l'ordre.
enum Gravite { critique, attention, information }

class Alerte {
  final Gravite gravite;
  final IconData icone;
  final String titre;
  final String detail;
  final String? conseil;

  const Alerte(this.gravite, this.icone, this.titre, this.detail,
      {this.conseil});

  Color get couleur => switch (gravite) {
        Gravite.critique => Palette.rouge,
        Gravite.attention => Palette.orFonce,
        Gravite.information => Palette.bleu,
      };
}

/// Ce qui mérite votre attention aujourd'hui, calculé à partir de ce qui
/// est déjà saisi. Rien n'est inventé : chaque alerte dit d'où elle sort.
class EcranAlertes extends StatelessWidget {
  const EcranAlertes({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final alertes = calculer(etat);

    final critiques =
        alertes.where((a) => a.gravite == Gravite.critique).length;
    final attentions =
        alertes.where((a) => a.gravite == Gravite.attention).length;

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (alertes.isEmpty)
            Bloc(
              fond: Palette.vert.withValues(alpha: 0.07),
              bordure: Palette.vert.withValues(alpha: 0.25),
              padding: const EdgeInsets.all(28),
              enfant: Column(children: [
                const Icon(Icons.verified_rounded,
                    size: 52, color: Palette.vertMoyen),
                const SizedBox(height: 14),
                Text('Tout va bien',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Aucune anomalie détectée sur vos fermes.\n'
                  'Production, stocks, présences et saisies : rien à signaler.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ]),
            )
          else ...[
            GrilleChiffres([
              CarteChiffre(
                  libelle: 'À traiter d’urgence',
                  valeur: '$critiques',
                  couleur: Palette.rouge,
                  icone: Icons.priority_high_rounded),
              CarteChiffre(
                  libelle: 'À surveiller',
                  valeur: '$attentions',
                  couleur: Palette.orFonce,
                  icone: Icons.visibility_outlined),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            for (final a in alertes) _carte(context, a),
          ],
          const SizedBox(height: 20),
          Bloc(
            padding: const EdgeInsets.all(15),
            enfant: Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Theme.of(context).hintColor),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Ces alertes se recalculent à chaque ouverture, à partir '
                  'des saisies validées. Elles ne remplacent pas votre œil : '
                  'elles vous disent seulement où regarder en premier.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _carte(BuildContext context, Alerte a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: a.couleur),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(a.icone, size: 19, color: a.couleur),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(a.titre,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: a.couleur)),
                    ),
                  ]),
                  const SizedBox(height: 7),
                  Text(a.detail,
                      style: Theme.of(context).textTheme.bodyMedium),
                  if (a.conseil != null) ...[
                    const SizedBox(height: 9),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: a.couleur.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text('👉  ${a.conseil}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(height: 1.45)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // LE CALCUL
  // ══════════════════════════════════════════════════════════════════
  static List<Alerte> calculer(Etat etat) {
    final liste = <Alerte>[];
    final jourCourant = aujourdhui();

    // ── 1. Chute de ponte : le signal le plus précoce d'une maladie ──
    for (final b in etat.batiments) {
      if (b.nbPoules <= 0) continue;
      final serie = <int>[];
      for (var i = 1; i <= 7; i++) {
        final j = jourCourant.subtract(Duration(days: i));
        final p = etat.productions.where((x) =>
            x.batimentId == b.id && x.date != null && iso(x.date!) == iso(j));
        if (p.isNotEmpty) serie.add(p.fold<int>(0, (s, x) => s + x.oeufs));
      }
      if (serie.length < 3) continue;
      final moyenne = serie.reduce((a, c) => a + c) / serie.length;
      final aujourdHui = etat.productions
          .where((x) =>
              x.batimentId == b.id &&
              x.date != null &&
              iso(x.date!) == iso(jourCourant))
          .fold<int>(0, (s, x) => s + x.oeufs);
      if (aujourdHui > 0 && moyenne > 0 && aujourdHui < moyenne * 0.85) {
        final chute = ((1 - aujourdHui / moyenne) * 100).round();
        liste.add(Alerte(
          chute >= 25 ? Gravite.critique : Gravite.attention,
          Icons.trending_down_rounded,
          'Chute de ponte — ${b.nom}',
          '${nb(aujourdHui)} œufs aujourd’hui contre ${nb(moyenne.round())} '
              'en moyenne ces 7 derniers jours, soit −$chute %.'
              '${etat.estAdmin ? ' (${etat.nomFerme(b.fermeId)})' : ''}',
          conseil:
              'Une baisse brutale précède souvent la maladie. Vérifiez l’eau, '
              'l’aliment et la température du bâtiment, et regardez s’il y a '
              'des poules abattues.',
        ));
      }
    }

    // ── 2. Bâtiments sans saisie aujourd'hui ──
    final sansSaisie = etat.batiments.where((b) => !etat.productions.any((p) =>
        p.batimentId == b.id &&
        p.date != null &&
        iso(p.date!) == iso(jourCourant)));
    if (sansSaisie.isNotEmpty && DateTime.now().hour >= 12) {
      liste.add(Alerte(
        Gravite.attention,
        Icons.egg_outlined,
        '${sansSaisie.length} bâtiment(s) sans production saisie',
        sansSaisie.map((b) => b.nom).join(', '),
        conseil:
            'La collecte du matin n’a peut-être pas été enregistrée. '
            'Un jour manquant fausse les moyennes et le taux de ponte.',
      ));
    }

    // ── 3. Stocks ──
    for (final s in etat.stocks.where((s) => s.critique)) {
      liste.add(Alerte(
        Gravite.critique,
        Icons.inventory_2_outlined,
        'Stock critique — ${s.nom}',
        'Il reste ${nb(s.quantite)} ${s.unite}, pour un seuil d’alerte de '
            '${nb(s.seuilMin)} ${s.unite}.'
            '${etat.estAdmin ? ' (${etat.nomFerme(s.fermeId)})' : ''}',
        conseil: s.nom.toLowerCase().contains('aliment')
            ? 'Une rupture d’aliment fait chuter la ponte en 48 h, et elle '
                'met des semaines à remonter. À commander en priorité.'
            : 'Prévoyez le réapprovisionnement avant la rupture.',
      ));
    }
    for (final s in etat.stocks.where((s) => s.faible)) {
      liste.add(Alerte(
        Gravite.attention,
        Icons.inventory_outlined,
        'Stock faible — ${s.nom}',
        'Il reste ${nb(s.quantite)} ${s.unite}.'
            '${etat.estAdmin ? ' (${etat.nomFerme(s.fermeId)})' : ''}',
      ));
    }

    // ── 4. Signalements urgents non traités ──
    final urgents = etat.signalements
        .where((s) => s.ouvert && s.priorite == 'urgent')
        .toList();
    for (final s in urgents) {
      final jours = s.date == null
          ? 0
          : jourCourant.difference(s.date!).inDays;
      liste.add(Alerte(
        jours >= 1 ? Gravite.critique : Gravite.attention,
        Icons.warning_amber_rounded,
        'Signalement urgent — ${s.titre}',
        '${etat.nomPersonne(s.auteurId)}, ${jours == 0 ? 'aujourd’hui' : 'il y a $jours jour(s)'}'
            '${etat.estAdmin ? ' · ${etat.nomFerme(s.fermeId)}' : ''}.'
            '${s.description.isEmpty ? '' : ' ${s.description}'}',
        conseil: jours >= 1
            ? 'Ouvert depuis plus d’un jour. Traitez-le ou expliquez au '
                'fermier ce qui a été décidé.'
            : null,
      ));
    }

    // ── 5. Saisies qui dorment ──
    final cible = etat.statutAValider;
    final enAttente = [
      ...etat.recettes.where((r) => r.statut == cible).map((r) => r.date),
      ...etat.depenses.where((d) => d.statut == cible).map((d) => d.date),
      ...etat.productions.where((p) => p.statut == cible).map((p) => p.date),
      ...etat.depots.where((d) => d.statut == cible).map((d) => d.date),
    ].whereType<DateTime>().toList();
    if (enAttente.isNotEmpty) {
      final plusVieille = enAttente.reduce((a, b) => a.isBefore(b) ? a : b);
      final jours = jourCourant.difference(plusVieille).inDays;
      if (jours >= 2) {
        liste.add(Alerte(
          jours >= 5 ? Gravite.critique : Gravite.attention,
          Icons.hourglass_top_rounded,
          '${enAttente.length} saisie(s) attendent votre validation',
          'La plus ancienne date du ${jour(plusVieille)}, il y a $jours jours.',
          conseil:
              'Tant qu’elles ne sont pas validées, elles ne comptent dans '
              'aucun total : vos chiffres du mois sont donc faux de ce montant.',
        ));
      }
    }

    // ── 6. Personne au travail ──
    if (etat.estAdmin || etat.estGerant) {
      final attendus = etat.personnes
          .where((p) => p.estFermier && !p.suspendu && p.fermeId != null)
          .toList();
      final pointes =
          etat.pointages.where((p) => iso(p.debut.toLocal()) == iso(jourCourant));
      final absents = attendus
          .where((p) => !pointes.any((pt) => pt.profilId == p.id))
          .toList();
      if (absents.isNotEmpty && DateTime.now().hour >= 9) {
        liste.add(Alerte(
          Gravite.information,
          Icons.person_off_outlined,
          '${absents.length} fermier(s) n’ont pas pointé aujourd’hui',
          absents.map((p) => p.nomComplet).join(', '),
          conseil:
              'Sans pointage, ils ne peuvent rien saisir. Vérifiez qu’ils '
              'ne sont pas bloqués devant l’application.',
        ));
      }
    }

    // ── 7. Fermes sans gérant ──
    if (etat.estAdmin) {
      for (final f in etat.fermes.where((f) => f.gerantId == null && f.active)) {
        liste.add(Alerte(
          Gravite.information,
          Icons.manage_accounts_outlined,
          'Ferme sans gérant — ${f.nom}',
          'Personne ne valide les saisies de cette ferme.',
          conseil:
              'Les saisies de ses fermiers resteront en attente indéfiniment. '
              'Attribuez-lui un gérant depuis la fiche de la ferme.',
        ));
      }
    }

    // Le plus grave en premier.
    liste.sort((a, b) => a.gravite.index.compareTo(b.gravite.index));
    return liste;
  }

  /// Combien d'alertes graves — pour la pastille de la barre du bas.
  static int compte(Etat etat) => calculer(etat)
      .where((a) => a.gravite != Gravite.information)
      .length;
}
