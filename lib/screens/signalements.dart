import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import 'formulaires.dart';

/// Ce que les fermiers remontent au gérant : maladie, casse, urgence.
class EcranSignalements extends StatefulWidget {
  const EcranSignalements({super.key});

  @override
  State<EcranSignalements> createState() => _EcranSignalementsState();
}

class _EcranSignalementsState extends State<EcranSignalements> {
  bool _seulementOuverts = true;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final lignes = etat.signalements
        .where((s) => !_seulementOuverts || s.ouvert)
        .toList();
    final urgents = etat.signalements
        .where((s) => s.ouvert && s.priorite == 'urgent')
        .length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (urgents > 0) ...[
              Bandeau(
                titre: '$urgents signalement(s) urgent(s)',
                texte: 'À traiter en priorité.',
                couleur: Palette.rouge,
                icone: Icons.priority_high_rounded,
              ),
              const SizedBox(height: 14),
            ],
            Row(children: [
              FilterChip(
                selected: _seulementOuverts,
                label: const Text('Ouverts seulement'),
                onSelected: (v) => setState(() => _seulementOuverts = v),
              ),
              const Spacer(),
              Text('${lignes.length} affiché(s)',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 14),
            if (lignes.isEmpty)
              Bloc(
                  enfant: Vide(
                      _seulementOuverts
                          ? 'Aucun signalement en cours'
                          : 'Aucun signalement',
                      icone: Icons.check_circle_outline_rounded,
                      action: etat.estFermier ? 'Signaler un problème' : null,
                      auClic: etat.estFermier
                          ? () => formulaireSignalement(context)
                          : null))
            else
              for (final s in lignes) _carte(context, etat, s),
          ],
        ),
      ),
      floatingActionButton: etat.estFermier
          ? FloatingActionButton.extended(
              backgroundColor: Palette.orFonce,
              foregroundColor: Colors.white,
              onPressed: () => formulaireSignalement(context),
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text('Signaler'),
            )
          : null,
    );
  }

  Widget _carte(BuildContext context, Etat etat, Signalement s) {
    final c = couleurPriorite(s.priorite);
    final peutTraiter = (etat.estGerant || etat.estAdmin) && s.ouvert;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(height: 4, width: double.infinity, color: c),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Text(s.titre,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Etiquette(
                    switch (s.priorite) {
                      'urgent' => 'Urgent',
                      'normal' => 'Normal',
                      _ => 'Info',
                    },
                    couleur: c),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.person_outline_rounded,
                    size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                      '${etat.nomPersonne(s.auteurId)} · ${jour(s.date)}'
                      '${s.batimentId != null ? ' · ${etat.batiment(s.batimentId)?.nom ?? ''}' : ''}'
                      '${etat.estAdmin ? ' · ${etat.nomFerme(s.fermeId)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                if (!s.ouvert)
                  const Etiquette('Traité',
                      couleur: Palette.vert, icone: Icons.check_rounded),
              ]),
              if (s.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(s.description,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
              if (s.reponse.isNotEmpty) ...[
                const SizedBox(height: 10),
                Bandeau(
                  titre: 'Réponse du gérant',
                  texte: s.reponse,
                  couleur: Palette.vert,
                  icone: Icons.reply_rounded,
                ),
              ],
            ]),
          ),
          if (peutTraiter) ...[
            const Divider(height: 1),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.vertMoyen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const RoundedRectangleBorder()),
                onPressed: () => _traiter(context, etat, s),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 19),
                label: const Text('Marquer comme traité'),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _traiter(
      BuildContext context, Etat etat, Signalement s) async {
    final reponse = await demanderTexte(context,
        titre: 'Ce qui a été fait',
        indice: 'Décrivez l’action menée (facultatif)',
        ok: 'Clôturer');
    if (reponse == null || !context.mounted) return;
    final e = await etat.agir(() => Api.majSignalement(s.id, {
          'statut': 'traite',
          'reponse': reponse,
        }));
    if (context.mounted) {
      message(context, e ?? 'Signalement clôturé', erreur: e != null);
    }
  }
}
