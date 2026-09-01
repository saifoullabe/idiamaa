import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/photos.dart';
import 'formulaires.dart';

/// Les rapports d'activité que les fermiers envoient à leur gérant.
class EcranRapports extends StatelessWidget {
  const EcranRapports({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final lignes = etat.rapports;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (lignes.isEmpty)
              Bloc(
                  enfant: Vide(
                      etat.estFermier
                          ? 'Vous n’avez encore envoyé aucun rapport'
                          : 'Aucun rapport reçu des fermiers',
                      icone: Icons.description_outlined,
                      action: etat.estFermier ? 'Écrire un rapport' : null,
                      auClic: etat.estFermier
                          ? () => formulaireRapport(context)
                          : null))
            else
              for (final r in lignes) _carte(context, etat, r),
          ],
        ),
      ),
      floatingActionButton: etat.estFermier
          ? FloatingActionButton.extended(
              backgroundColor: Palette.bleu,
              foregroundColor: Colors.white,
              onPressed: () => formulaireRapport(context),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Nouveau rapport'),
            )
          : null,
    );
  }

  Widget _carte(BuildContext context, Etat etat, Rapport r) {
    final estLeMien = r.auteurId == etat.moi!.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Bloc(
        enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: Palette.bleu.withValues(alpha: 0.13),
                  child: const Icon(Icons.description_rounded,
                      color: Palette.bleu, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.titre,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                          '${etat.nomPersonne(r.auteurId)} · ${jour(r.date)}'
                          '${etat.estAdmin ? ' · ${etat.nomFerme(r.fermeId)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (estLeMien || etat.estAdmin || etat.estGerant)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _supprimer(context, etat, r),
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: Theme.of(context).hintColor),
                  ),
              ]),
              if (r.activites.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('ACTIVITÉS EFFECTUÉES',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 5),
                Text(r.activites,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (r.observations.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('OBSERVATIONS',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Palette.or.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(r.observations,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
              if (r.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                GaleriePhotos(r.photos),
              ],
            ]),
      ),
    );
  }

  Future<void> _supprimer(BuildContext context, Etat etat, Rapport r) async {
    final ok = await confirmer(context,
        titre: 'Supprimer ce rapport ?',
        texte: r.titre,
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerRapport(r.id));
    if (context.mounted) {
      message(context, e ?? 'Rapport supprimé', erreur: e != null);
    }
  }
}
