import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../widgets/communs.dart';

/// Le pointage du fermier : arrivée, chronomètre, sortie, historique.
class EcranPointage extends StatefulWidget {
  const EcranPointage({super.key});

  @override
  State<EcranPointage> createState() => _EcranPointageState();
}

class _EcranPointageState extends State<EcranPointage> {
  Timer? _horloge;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    // Le chronomètre avance seul tant que la personne est en ligne.
    _horloge = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<Etat>().enLigne) setState(() {});
    });
  }

  @override
  void dispose() {
    _horloge?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final enLigne = etat.enLigne;
    final couleur = enLigne ? Palette.vertMoyen : Palette.gris;

    final miens = etat.pointages
        .where((p) => p.profilId == etat.moi!.id)
        .toList();
    final totalSemaine = miens
        .where((p) =>
            p.duree != null &&
            p.debut.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .fold<int>(0, (s, p) => s + p.duree!);

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          // ── Statut ──
          Bloc(
            fond: couleur.withValues(alpha: 0.09),
            bordure: couleur.withValues(alpha: 0.3),
            padding: const EdgeInsets.all(20),
            enfant: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: couleur,
                    boxShadow: enLigne
                        ? [
                            BoxShadow(
                                color: couleur.withValues(alpha: 0.45),
                                blurRadius: 12,
                                spreadRadius: 2)
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(enLigne ? 'En ligne — au travail' : 'Hors ligne',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: couleur)),
              ]),
              const SizedBox(height: 16),
              if (enLigne) ...[
                Text('TEMPS TRAVAILLÉ AUJOURD’HUI',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                Text(chrono(etat.monPointage!.dureeSecondes),
                    style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: Palette.vert)),
                const SizedBox(height: 4),
                Text('Arrivée pointée à ${heureSec(etat.monPointage!.debut)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ] else
                Text(
                    'Pointez votre arrivée pour pouvoir saisir\n'
                    'les productions, recettes et dépenses.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ),
          const SizedBox(height: 18),

          // ── Le grand bouton ──
          SizedBox(
            height: 96,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: enLigne ? Palette.rouge : Palette.vertMoyen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: _occupe ? null : () => _basculer(etat),
              child: _occupe
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            enLigne
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                            size: 28,
                            color: Colors.white),
                        const SizedBox(height: 6),
                        Text(
                            enLigne
                                ? 'POINTER LA SORTIE'
                                : 'POINTER L’ARRIVÉE',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: Colors.white)),
                        Text(
                            enLigne
                                ? 'Fin de la journée de travail'
                                : 'Début de la journée de travail',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 18),

          GrilleChiffres([
            CarteChiffre(
                libelle: 'Cette semaine',
                valeur: duree(totalSemaine),
                complement:
                    '${miens.where((p) => p.duree != null && p.debut.isAfter(DateTime.now().subtract(const Duration(days: 7)))).length} journée(s)',
                couleur: Palette.bleu,
                icone: Icons.calendar_view_week_rounded),
            CarteChiffre(
                libelle: 'Total enregistré',
                valeur: duree(
                    miens.fold<int>(0, (s, p) => s + (p.duree ?? 0))),
                complement: '${miens.length} pointage(s)',
                couleur: Palette.vert,
                icone: Icons.timelapse_rounded),
          ], largeurMin: 150),

          const TitreSection('Mon historique', emoji: '📅'),
          if (miens.isEmpty)
            const Bloc(
                enfant: Vide('Aucun pointage enregistré',
                    icone: Icons.history_rounded))
          else
            Bloc(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              enfant: Column(children: [
                for (final p in miens.take(40))
                  ListTile(
                    dense: true,
                    leading: Icon(
                        p.enCours
                            ? Icons.play_circle_fill_rounded
                            : Icons.check_circle_rounded,
                        color: p.enCours ? Palette.vertClair : Palette.gris),
                    title: Text(jour(p.debut),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${heure(p.debut)} → ${p.fin == null ? 'en cours' : heure(p.fin)}'),
                    trailing: Text(
                        p.enCours ? 'En cours' : duree(p.duree),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: p.enCours
                                ? Palette.vertMoyen
                                : Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color)),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _basculer(Etat etat) async {
    final sortie = etat.enLigne;
    if (sortie) {
      final ok = await confirmer(context,
          titre: 'Pointer la sortie ?',
          texte:
              'Vous aurez travaillé ${duree(etat.monPointage!.dureeSecondes)} aujourd’hui.\n'
              'Après la sortie, vous ne pourrez plus saisir sans repointer.',
          ok: 'Pointer la sortie',
          icone: Icons.logout_rounded);
      if (!ok || !mounted) return;
    }
    setState(() => _occupe = true);
    final e = await etat.basculerPointage();
    if (!mounted) return;
    setState(() => _occupe = false);
    message(
        context,
        e ??
            (sortie
                ? 'Sortie enregistrée — bonne fin de journée'
                : 'Arrivée enregistrée — bonne journée'),
        erreur: e != null);
  }
}
