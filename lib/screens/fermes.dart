import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import 'formulaires.dart';

class EcranFermes extends StatelessWidget {
  const EcranFermes({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: etat.fermes.isEmpty
            ? ListView(children: [
                const SizedBox(height: 60),
                Vide('Aucune ferme enregistrée',
                    icone: Icons.holiday_village_outlined,
                    action: 'Créer la première ferme',
                    auClic: () => formulaireFerme(context)),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  for (final f in etat.fermes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: CarteFerme(f, detaillee: true),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => formulaireFerme(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle ferme'),
      ),
    );
  }
}

/// La carte d'une ferme : ses chiffres, son équipe, et ses commandes.
class CarteFerme extends StatelessWidget {
  final Ferme ferme;
  final bool detaillee;

  const CarteFerme(this.ferme, {super.key, this.detaillee = false});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final gerant = etat.personne(ferme.gerantId);
    final fermiers = etat.fermiersDe(ferme.id);
    final bats = etat.batimentsDe(ferme.id);
    final ventes = etat.totalRecettes(fermeId: ferme.id);
    final depots = etat.totalDepotsRecus(fermeId: ferme.id);
    final depenses = etat.totalDepenses(fermeId: ferme.id);

    final couleurStatut = switch (ferme.statut) {
      'Actif' => Palette.vert,
      'Maintenance' => Palette.orFonce,
      'Suspendue' => Palette.rouge,
      _ => Palette.gris,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // En-tête
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A2E0A), Palette.vert],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🏚️  ${ferme.nom}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      '📍 ${ferme.ville.isEmpty ? '—' : ferme.ville} · '
                      '${bats.length} bâtiment(s) · alvéole ${gnf(ferme.prixAlveole)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11.5)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(ferme.statut,
                  style: TextStyle(
                      color: couleurStatut,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),

        // Équipe
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(children: [
            LigneInfo('Gérant', gerant?.nomComplet ?? 'Non assigné',
                icone: Icons.manage_accounts_outlined),
            LigneInfo(
                'Fermiers',
                fermiers.isEmpty
                    ? 'Aucun'
                    : fermiers.map((f) => f.nomComplet).join(' · '),
                icone: Icons.agriculture_outlined),
          ]),
        ),

        // Chiffres
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: Row(children: [
            _mini(context, 'Ventes', ventes, Palette.vert),
            _mini(context, 'Dépôts', depots, Palette.bleu),
            _mini(context, 'Dépenses', depenses, Palette.rouge),
          ]),
        ),

        if (detaillee) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(children: [
              Expanded(
                child: Text('Bâtiments (${bats.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: () =>
                    formulaireBatiment(context, fermeId: ferme.id),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Ajouter'),
              ),
            ]),
          ),
          if (bats.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Vide('Aucun bâtiment', icone: Icons.warehouse_outlined),
            )
          else
            for (final b in bats)
              ListTile(
                dense: true,
                leading: Icon(Icons.warehouse_rounded,
                    color: switch (b.etat) {
                      'Bon' => Palette.vert,
                      'Correct' => Palette.orFonce,
                      _ => Palette.rouge,
                    }),
                title: Text(b.nom,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${b.type} · ${nb(b.nbPoules)} poules · ${b.etat}'),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                    PopupMenuItem(
                        value: 'supprimer', child: Text('Supprimer')),
                  ],
                  onSelected: (v) async {
                    if (v == 'modifier') {
                      formulaireBatiment(context, batiment: b);
                    } else {
                      final ok = await confirmer(context,
                          titre: 'Supprimer ${b.nom} ?',
                          texte:
                              'Les productions déjà saisies sur ce bâtiment seront supprimées avec lui.',
                          ok: 'Supprimer',
                          danger: true,
                          icone: Icons.delete_outline_rounded);
                      if (ok && context.mounted) {
                        final e = await context
                            .read<Etat>()
                            .agir(() => Api.supprimerBatiment(b.id));
                        if (context.mounted) {
                          message(context, e ?? 'Bâtiment supprimé',
                              erreur: e != null);
                        }
                      }
                    }
                  },
                ),
              ),
        ],

        // Commandes
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              _bouton(context, Icons.group_add_rounded, 'Équipe', Palette.bleu,
                  () => formulaireAttribution(context, ferme)),
              _bouton(context, Icons.edit_rounded, 'Modifier', Palette.gris,
                  () => formulaireFerme(context, ferme: ferme)),
              _bouton(context, Icons.sell_rounded, 'Prix alvéole', Palette.or,
                  () => _changerPrix(context, ferme)),
              _bouton(
                  context,
                  ferme.suspendue
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  ferme.suspendue ? 'Réactiver' : 'Suspendre',
                  ferme.suspendue ? Palette.vert : Palette.orFonce,
                  () => _basculerSuspension(context, ferme)),
              _bouton(context, Icons.delete_outline_rounded, 'Supprimer',
                  Palette.rouge, () => _supprimer(context, ferme)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _mini(BuildContext context, String libelle, int valeur, Color c) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(children: [
            Text(libelle, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 3),
            FittedBox(
              child: Text(gnfCourt(valeur),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: c)),
            ),
          ]),
        ),
      );

  Widget _bouton(BuildContext context, IconData icone, String texte, Color c,
          VoidCallback auClic) =>
      TextButton.icon(
        onPressed: auClic,
        style: TextButton.styleFrom(
          foregroundColor: c,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icone, size: 17),
        label: Text(texte, style: const TextStyle(fontSize: 12)),
      );

  Future<void> _changerPrix(BuildContext context, Ferme f) async {
    final prix = await demanderNombre(
      context,
      titre: 'Prix de l’alvéole',
      sousTitre:
          '${f.nom} — actuellement ${gnf(f.prixAlveole)}.\nLe nouveau prix s’applique aussi à tous ses bâtiments.',
      valeurInitiale: '${f.prixAlveole}',
      suffixe: 'GNF',
      icone: Icons.sell_rounded,
      couleur: Palette.or,
    );
    if (prix == null || prix <= 0 || !context.mounted) return;
    final e = await context
        .read<Etat>()
        .agir(() => Api.changerPrixAlveole(f.id, prix.round()));
    if (context.mounted) {
      message(context, e ?? 'Prix mis à jour : ${gnf(prix)}', erreur: e != null);
    }
  }

  Future<void> _basculerSuspension(BuildContext context, Ferme f) async {
    final suspendre = !f.suspendue;
    final ok = await confirmer(
      context,
      titre: suspendre ? 'Suspendre ${f.nom} ?' : 'Réactiver ${f.nom} ?',
      texte: suspendre
          ? 'Le gérant et les fermiers de cette ferme ne pourront plus se connecter. Les données restent en place.'
          : 'L’équipe de cette ferme pourra de nouveau se connecter.',
      ok: suspendre ? 'Suspendre' : 'Réactiver',
      danger: suspendre,
      icone: suspendre ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    if (!ok || !context.mounted) return;
    final e = await context.read<Etat>().agir(() =>
        Api.majFerme(f.id, {'statut': suspendre ? 'Suspendue' : 'Actif'}));
    if (context.mounted) {
      message(context, e ?? (suspendre ? 'Ferme suspendue' : 'Ferme réactivée'),
          erreur: e != null);
    }
  }

  Future<void> _supprimer(BuildContext context, Ferme f) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer ${f.nom} ?',
      texte:
          'Tout ce qui appartient à cette ferme disparaît avec elle : bâtiments, '
          'productions, recettes, dépenses, dépôts, stocks. C’est définitif.\n\n'
          'Pour fermer une ferme sans rien perdre, suspendez-la plutôt.',
      ok: 'Supprimer définitivement',
      danger: true,
      icone: Icons.delete_forever_rounded,
    );
    if (!ok || !context.mounted) return;
    final e =
        await context.read<Etat>().agir(() => Api.supprimerFerme(f.id));
    if (context.mounted) {
      message(context, e ?? 'Ferme supprimée', erreur: e != null);
    }
  }
}
