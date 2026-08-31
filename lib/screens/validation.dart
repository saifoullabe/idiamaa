import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';

/// L'écran où le gérant valide les saisies de ses fermiers,
/// et où l'administrateur valide celles de ses gérants.
class EcranValidation extends StatelessWidget {
  const EcranValidation({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final cible = etat.statutAValider;

    final recettes =
        etat.recettes.where((r) => r.statut == cible).toList();
    final depenses =
        etat.depenses.where((d) => d.statut == cible).toList();
    final depots = etat.depots.where((d) => d.statut == cible).toList();

    // Les productions se valident par journée de travail, pas alvéole
    // par alvéole : c'est ainsi qu'elles ont été saisies.
    final groupes = <String, List<Production>>{};
    for (final p in etat.productions.where((p) => p.statut == cible)) {
      groupes
          .putIfAbsent('${iso(p.date ?? aujourdhui())}|${p.auteurId}', () => [])
          .add(p);
    }

    final total =
        recettes.length + depenses.length + depots.length + groupes.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: total == 0
            ? ListView(children: [
                const SizedBox(height: 70),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Bloc(
                    fond: Palette.vert.withValues(alpha: 0.07),
                    bordure: Palette.vert.withValues(alpha: 0.25),
                    padding: const EdgeInsets.all(28),
                    enfant: Column(children: [
                      const Icon(Icons.verified_rounded,
                          size: 52, color: Palette.vertMoyen),
                      const SizedBox(height: 14),
                      Text('Tout est à jour',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        etat.estAdmin
                            ? 'Aucune saisie de gérant n’attend votre validation.'
                            : 'Aucune saisie de fermier n’attend votre validation.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ]),
                  ),
                ),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Bandeau(
                    titre: '$total saisie(s) en attente',
                    texte: etat.estAdmin
                        ? 'Saisies de vos gérants. Une fois validées, elles entrent dans les totaux.'
                        : 'Saisies de vos fermiers. Une fois validées, elles entrent dans les totaux.',
                    couleur: Palette.orFonce,
                    icone: Icons.hourglass_top_rounded,
                    action: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Palette.vert,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10)),
                      onPressed: () => _toutValider(context, etat, {
                        'recettes': recettes.map((e) => e.id).toList(),
                        'depenses': depenses.map((e) => e.id).toList(),
                        'productions': groupes.values
                            .expand((g) => g.map((p) => p.id))
                            .toList(),
                        'depots': depots.map((e) => e.id).toList(),
                      }, total),
                      child: const Text('Tout valider'),
                    ),
                  ),
                  if (groupes.isNotEmpty) ...[
                    const TitreSection('Productions', emoji: '🥚'),
                    for (final entree in groupes.entries)
                      _carteProduction(context, etat, entree.value),
                  ],
                  if (recettes.isNotEmpty) ...[
                    const TitreSection('Recettes', emoji: '💰'),
                    for (final r in recettes) _carteRecette(context, etat, r),
                  ],
                  if (depenses.isNotEmpty) ...[
                    const TitreSection('Dépenses', emoji: '📤'),
                    for (final d in depenses) _carteDepense(context, etat, d),
                  ],
                  if (depots.isNotEmpty) ...[
                    const TitreSection('Dépôts d’argent', emoji: '🏦'),
                    for (final d in depots) _carteDepot(context, etat, d),
                  ],
                ],
              ),
      ),
    );
  }

  // ── Cartes ────────────────────────────────────────────────────────
  Widget _carteProduction(
      BuildContext context, Etat etat, List<Production> lot) {
    final oeufs = lot.fold<int>(0, (s, p) => s + p.oeufs);
    final valeur = lot.fold<int>(0, (s, p) => s + p.valeur);
    final alveoles = lot.fold<int>(0, (s, p) => s + p.nbAlveoles);

    return _coque(
      context,
      entete: Row(children: [
        const Text('🥚', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${lot.length} bâtiment(s) — ${jour(lot.first.date)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  '${etat.nomPersonne(lot.first.auteurId)} · ${etat.nomFerme(lot.first.fermeId)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ]),
      corps: Column(children: [
        for (final p in lot)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                    etat.batiment(p.batimentId)?.nom ?? 'Bâtiment',
                    style: const TextStyle(fontSize: 13)),
              ),
              Text('${p.nbAlveoles} alv.',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              Text('${nb(p.oeufs)} 🥚',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Palette.vert)),
            ]),
          ),
        const Divider(height: 20),
        Row(children: [
          Expanded(
            child: Text('Total : $alveoles alvéoles · ${nb(oeufs)} œufs',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          Text(gnf(valeur),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Palette.orFonce)),
        ]),
      ]),
      ids: lot.map((p) => p.id).toList(),
      table: 'productions',
      etat: etat,
    );
  }

  Widget _carteRecette(BuildContext context, Etat etat, Recette r) => _coque(
        context,
        entete: Row(children: [
          const Text('💰', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.produit,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    '${etat.nomPersonne(r.auteurId)} · ${jour(r.date)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Montant(r.montant),
        ]),
        corps: Column(children: [
          if (r.quantite > 0)
            LigneInfo('Quantité',
                '${nb(r.quantite)} × ${gnf(r.prixUnitaire)}'),
          if (r.description.isNotEmpty)
            LigneInfo('Client / Note', r.description),
        ]),
        ids: [r.id],
        table: 'recettes',
        etat: etat,
      );

  Widget _carteDepense(BuildContext context, Etat etat, Depense d) {
    final cat = categorie(d.categorie);
    return _coque(
      context,
      entete: Row(children: [
        Text(cat.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.article,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                  '${cat.libelle} · ${etat.nomPersonne(d.auteurId)} · ${jour(d.date)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Montant(d.montant, negatif: true),
      ]),
      corps: Column(children: [
        if (d.quantite > 0)
          LigneInfo('Quantité',
              '${nb(d.quantite)} ${d.unite} × ${gnf(d.prixUnitaire)}'),
        if (d.description.isNotEmpty) LigneInfo('Remarque', d.description),
      ]),
      ids: [d.id],
      table: 'depenses',
      etat: etat,
    );
  }

  Widget _carteDepot(BuildContext context, Etat etat, Depot d) => _coque(
        context,
        entete: Row(children: [
          const Text('🏦', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gnf(d.montant),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${etat.nomPersonne(d.auteurId)} · ${jour(d.date)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ]),
        corps: Column(children: [
          if (d.reference.isNotEmpty) LigneInfo('N° de reçu', d.reference),
          if (d.motif.isNotEmpty) LigneInfo('Motif', d.motif),
          if (d.fichiers.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final f in d.fichiers)
                    ActionChip(
                      avatar: const Icon(Icons.attachment_rounded, size: 16),
                      label: const Text('Voir le reçu'),
                      onPressed: () => _ouvrirPiece(context, f),
                    ),
                ],
              ),
            ),
        ]),
        ids: [d.id],
        table: 'depots',
        etat: etat,
      );

  /// L'habillage commun : le contenu, puis les deux boutons de décision.
  Widget _coque(
    BuildContext context, {
    required Widget entete,
    required Widget corps,
    required List<String> ids,
    required String table,
    required Etat etat,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(children: [
              entete,
              const SizedBox(height: 8),
              corps,
            ]),
          ),
          const Divider(height: 1),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.rouge,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder()),
                onPressed: () => _rejeter(context, etat, table, ids),
                icon: const Icon(Icons.close_rounded, size: 19),
                label: const Text('Rejeter'),
              ),
            ),
            Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.vertMoyen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder()),
                onPressed: () => _valider(context, etat, table, ids),
                icon: const Icon(Icons.check_rounded, size: 19),
                label: const Text('Valider'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Décisions ─────────────────────────────────────────────────────
  Future<void> _valider(BuildContext context, Etat etat, String table,
      List<String> ids) async {
    final e = await etat
        .agir(() => Api.valider(table, ids, roleValidateur: etat.role));
    if (context.mounted) {
      message(context, e ?? 'Validé — la saisie compte à partir de maintenant',
          erreur: e != null);
    }
  }

  Future<void> _rejeter(BuildContext context, Etat etat, String table,
      List<String> ids) async {
    final motif = await demanderTexte(context,
        titre: 'Motif du rejet',
        indice: 'Expliquez ce qui ne va pas (facultatif)',
        ok: 'Rejeter');
    if (motif == null || !context.mounted) return;
    final e = await etat.agir(() =>
        Api.rejeter(table, ids, motif.isEmpty ? 'Rejeté' : motif));
    if (context.mounted) {
      message(context, e ?? 'Saisie rejetée', erreur: e != null);
    }
  }

  Future<void> _toutValider(BuildContext context, Etat etat,
      Map<String, List<String>> parTable, int total) async {
    final ok = await confirmer(
      context,
      titre: 'Tout valider ?',
      texte:
          'Les $total saisies en attente seront validées d’un coup. '
          'Vérifiez-les avant, car cette action les fait entrer dans les comptes.',
      ok: 'Tout valider',
      icone: Icons.done_all_rounded,
    );
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() async {
      for (final entree in parTable.entries) {
        await Api.valider(entree.key, entree.value,
            roleValidateur: etat.role);
      }
    });
    if (context.mounted) {
      message(context, e ?? '$total saisie(s) validée(s)', erreur: e != null);
    }
  }

  void _ouvrirPiece(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBar(
            title: const Text('Reçu'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close_rounded)),
            ],
          ),
          Flexible(
            child: InteractiveViewer(
              child: Image.network(url,
                  errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(30),
                        child: Vide(
                            'Ce reçu est un fichier PDF — ouvrez-le depuis la liste des dépôts.',
                            icone: Icons.picture_as_pdf_outlined),
                      )),
            ),
          ),
        ]),
      ),
    );
  }
}
