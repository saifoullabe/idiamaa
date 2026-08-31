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

/// Le magasin de la ferme : ce qui rentre (achats) et ce qui sort
/// (consommation quotidienne).
class EcranStocks extends StatelessWidget {
  const EcranStocks({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final stocks = etat.stocks;
    final critiques = stocks.where((s) => s.critique).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (critiques.isNotEmpty) ...[
              Bandeau(
                titre: '${critiques.length} article(s) en rupture',
                texte: critiques.map((s) => s.nom).join(' · '),
                couleur: Palette.rouge,
                icone: Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 14),
            ],
            if (stocks.isEmpty)
              Bloc(
                  enfant: Vide('Aucun article en stock',
                      icone: Icons.inventory_2_outlined,
                      action: 'Créer le premier article',
                      auClic: () => formulaireStock(context)))
            else
              for (final s in stocks) _carte(context, etat, s),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => formulaireStock(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvel article'),
      ),
    );
  }

  Widget _carte(BuildContext context, Etat etat, Stock s) {
    final couleur = s.critique
        ? Palette.rouge
        : (s.faible ? Palette.orFonce : Palette.vert);
    final statut =
        s.critique ? 'Critique' : (s.faible ? 'Faible' : 'Suffisant');
    final cat = categorie(s.categorie);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Bloc(
        enfant: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.nom,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                      '${cat.titre} · seuil ${nb(s.seuilMin)} ${s.unite}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(nb(s.quantite),
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: couleur)),
              Text(s.unite, style: Theme.of(context).textTheme.bodySmall),
            ]),
            PopupMenuButton<String>(
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'mouvements', child: Text('Mouvements')),
                PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
              ],
              onSelected: (v) async {
                if (v == 'modifier') {
                  formulaireStock(context, stock: s);
                } else if (v == 'mouvements') {
                  _historique(context, etat, s);
                } else {
                  final ok = await confirmer(context,
                      titre: 'Supprimer ${s.nom} ?',
                      texte:
                          'L’article et son historique de mouvements seront effacés.',
                      ok: 'Supprimer',
                      danger: true,
                      icone: Icons.delete_outline_rounded);
                  if (ok && context.mounted) {
                    final e =
                        await etat.agir(() => Api.supprimerStock(s.id));
                    if (context.mounted) {
                      message(context, e ?? 'Article supprimé',
                          erreur: e != null);
                    }
                  }
                }
              },
            ),
          ]),
          const SizedBox(height: 12),
          Jauge(s.niveau, couleur: couleur),
          const SizedBox(height: 8),
          Row(children: [
            Text('0', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Etiquette('$statut (${s.niveau} %)', couleur: couleur),
            const Spacer(),
            Text('${nb(s.seuilMin * 3)} ${s.unite}',
                style: Theme.of(context).textTheme.labelSmall),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            if (etat.estGerant || etat.estAdmin)
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Palette.vert,
                      side: const BorderSide(color: Palette.vert)),
                  onPressed: () => _bouger(context, etat, s, true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Entrée'),
                ),
              ),
            if ((etat.estGerant || etat.estAdmin) &&
                (etat.estFermier || etat.estGerant || etat.estAdmin))
              const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Palette.rouge),
                onPressed: () => _bouger(context, etat, s, false),
                icon: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('Sortie'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _bouger(
      BuildContext context, Etat etat, Stock s, bool entree) async {
    if (!etat.peutSaisir) {
      message(context, etat.raisonBlocage ?? 'Action impossible', erreur: true);
      return;
    }
    final quantite = await demanderNombre(
      context,
      titre: entree ? 'Entrée de stock' : 'Sortie de stock',
      sousTitre:
          '${s.nom}\nStock actuel : ${nb(s.quantite)} ${s.unite}',
      suffixe: s.unite,
      icone: entree ? Icons.add_box_rounded : Icons.indeterminate_check_box_rounded,
      couleur: entree ? Palette.vert : Palette.rouge,
    );
    if (quantite == null || quantite <= 0 || !context.mounted) return;

    final e = await etat.agir(() => Api.bougerStock(
          stockId: s.id,
          entree: entree,
          quantite: quantite,
        ));
    if (context.mounted) {
      message(
          context,
          e ??
              '${entree ? '+' : '−'} ${nb(quantite)} ${s.unite} — nouveau stock : '
                  '${nb(entree ? s.quantite + quantite : s.quantite - quantite)} ${s.unite}',
          erreur: e != null);
    }
  }

  void _historique(BuildContext context, Etat etat, Stock s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (feuille) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controleur) => FutureBuilder<List<MouvementStock>>(
          future: Api.mouvements(s.id),
          builder: (c, capture) {
            if (!capture.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final mouvements = capture.data!;
            return ListView(
              controller: controleur,
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
              children: [
                Text('Mouvements — ${s.nom}',
                    style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Stock actuel : ${nb(s.quantite)} ${s.unite}',
                    style: Theme.of(c).textTheme.bodySmall),
                const SizedBox(height: 14),
                if (mouvements.isEmpty)
                  const Vide('Aucun mouvement enregistré',
                      icone: Icons.swap_vert_rounded)
                else
                  for (final m in mouvements)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: (m.estEntree
                                ? Palette.vert
                                : Palette.rouge)
                            .withValues(alpha: 0.13),
                        child: Icon(
                            m.estEntree
                                ? Icons.add_rounded
                                : Icons.remove_rounded,
                            color:
                                m.estEntree ? Palette.vert : Palette.rouge),
                      ),
                      title: Text(
                          '${m.estEntree ? '+' : '−'} ${nb(m.quantite)} ${m.unite}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${etat.nomPersonne(m.auteurId)} · ${depuis(m.creeLe)}'),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
