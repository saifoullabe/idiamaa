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

class EcranRecettes extends StatefulWidget {
  const EcranRecettes({super.key});

  @override
  State<EcranRecettes> createState() => _EcranRecettesState();
}

class _EcranRecettesState extends State<EcranRecettes> {
  String? _ferme;
  String? _auteur;
  DateTime? _mois;
  bool _seulementMesSaisies = false;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    var lignes = etat.recettes.where((r) {
      if (_ferme != null && r.fermeId != _ferme) return false;
      if (_auteur != null && r.auteurId != _auteur) return false;
      if (_seulementMesSaisies && r.auteurId != etat.moi!.id) return false;
      if (_mois != null &&
          (r.date == null ||
              r.date!.year != _mois!.year ||
              r.date!.month != _mois!.month)) return false;
      return true;
    }).toList();

    final valide = lignes
        .where((r) => r.statut == Statut.valide)
        .fold<int>(0, (s, r) => s + r.montant);
    final attente = lignes
        .where((r) => Statut.enAttente(r.statut))
        .fold<int>(0, (s, r) => s + r.montant);

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
                  libelle: 'Recettes validées',
                  valeur: gnfCourt(valide),
                  complement: '${lignes.where((r) => r.statut == Statut.valide).length} vente(s)',
                  couleur: Palette.vert,
                  icone: Icons.check_circle_rounded),
              CarteChiffre(
                  libelle: 'En attente',
                  valeur: gnfCourt(attente),
                  complement:
                      '${lignes.where((r) => Statut.enAttente(r.statut)).length} saisie(s)',
                  couleur: Palette.orFonce,
                  icone: Icons.hourglass_top_rounded),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            if (lignes.isEmpty)
              Bloc(
                  enfant: Vide('Aucune recette pour ce filtre',
                      icone: Icons.payments_outlined,
                      action: 'Enregistrer une vente',
                      auClic: () => formulaireRecette(context)))
            else
              for (final r in lignes) _carte(context, etat, r),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => formulaireRecette(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle vente'),
      ),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (etat.estAdmin)
          _menuFerme(context, etat),
        if (etat.estGerant) _menuAuteur(context, etat),
        if (etat.estFermier)
          FilterChip(
            selected: _seulementMesSaisies,
            label: const Text('Mes saisies'),
            avatar: const Icon(Icons.person_outline_rounded, size: 17),
            onSelected: (v) => setState(() => _seulementMesSaisies = v),
          ),
        const SizedBox(width: 8),
        _menuMois(context),
        if (_ferme != null ||
            _auteur != null ||
            _mois != null ||
            _seulementMesSaisies) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Effacer'),
            onPressed: () => setState(() {
              _ferme = null;
              _auteur = null;
              _mois = null;
              _seulementMesSaisies = false;
            }),
          ),
        ],
      ]),
    );
  }

  Widget _menuFerme(BuildContext context, Etat etat) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PopupMenuButton<String?>(
          onSelected: (v) => setState(() => _ferme = v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: null, child: Text('Toutes les fermes')),
            for (final f in etat.fermes)
              PopupMenuItem(value: f.id, child: Text(f.nom)),
          ],
          child: Chip(
            avatar: const Icon(Icons.holiday_village_outlined, size: 17),
            label: Text(_ferme == null ? 'Toutes les fermes' : etat.nomFerme(_ferme)),
            deleteIcon: const Icon(Icons.arrow_drop_down_rounded),
            onDeleted: null,
          ),
        ),
      );

  Widget _menuAuteur(BuildContext context, Etat etat) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PopupMenuButton<String?>(
          onSelected: (v) => setState(() => _auteur = v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: null, child: Text('Tout le monde')),
            for (final p in etat.personnes.where((p) => !p.estAdmin))
              PopupMenuItem(value: p.id, child: Text(p.nomComplet)),
          ],
          child: Chip(
            avatar: const Icon(Icons.person_outline_rounded, size: 17),
            label: Text(
                _auteur == null ? 'Tout le monde' : etat.nomPersonne(_auteur)),
          ),
        ),
      );

  Widget _menuMois(BuildContext context) {
    final maintenant = DateTime.now();
    return PopupMenuButton<DateTime?>(
      onSelected: (v) => setState(() => _mois = v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('Tous les mois')),
        for (var i = 0; i < 12; i++)
          PopupMenuItem(
            value: DateTime(maintenant.year, maintenant.month - i),
            child: Text(moisAnnee(DateTime(maintenant.year, maintenant.month - i))),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.calendar_month_outlined, size: 17),
        label: Text(_mois == null ? 'Tous les mois' : moisAnnee(_mois)),
      ),
    );
  }

  Widget _carte(BuildContext context, Etat etat, Recette r) {
    final peutSupprimer = etat.estAdmin ||
        etat.estGerant ||
        (r.auteurId == etat.moi!.id && Statut.enAttente(r.statut));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Bloc(
        enfant: Column(children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: Palette.vert.withValues(alpha: 0.12),
              child: const Icon(Icons.payments_rounded,
                  color: Palette.vert, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.produit,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      '${jour(r.date)}'
                      '${etat.estAdmin ? ' · ${etat.nomFerme(r.fermeId)}' : ''}'
                      ' · ${etat.nomPersonne(r.auteurId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Montant(r.montant),
              const SizedBox(height: 4),
              PuceStatut(r.statut, compact: true),
            ]),
            if (peutSupprimer)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'supprimer', child: Text('Supprimer')),
                ],
                onSelected: (_) => _supprimer(context, etat, r),
              ),
          ]),
          if (r.quantite > 0 || r.description.isNotEmpty) ...[
            const Divider(height: 20),
            Row(children: [
              if (r.quantite > 0)
                Expanded(
                  child: Text(
                      '${nb(r.quantite)} × ${gnf(r.prixUnitaire)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (r.description.isNotEmpty)
                Expanded(
                  flex: 2,
                  child: Text(r.description,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)),
                ),
            ]),
          ],
          if (r.statut == Statut.rejete && r.motifRejet.isNotEmpty) ...[
            const SizedBox(height: 10),
            Bandeau(
                titre: 'Rejetée',
                texte: r.motifRejet,
                couleur: Palette.rouge,
                icone: Icons.cancel_rounded),
          ],
        ]),
      ),
    );
  }

  Future<void> _supprimer(BuildContext context, Etat etat, Recette r) async {
    final ok = await confirmer(context,
        titre: 'Supprimer cette recette ?',
        texte: '${r.produit} — ${gnf(r.montant)} du ${jour(r.date)}.',
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerRecette(r.id));
    if (context.mounted) {
      message(context, e ?? 'Recette supprimée', erreur: e != null);
    }
  }
}
