import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import 'formulaires.dart';

/// Les mouvements d'argent entre l'administration et les fermes,
/// avec le reçu justificatif attaché.
class EcranDepots extends StatefulWidget {
  const EcranDepots({super.key});

  @override
  State<EcranDepots> createState() => _EcranDepotsState();
}

class _EcranDepotsState extends State<EcranDepots> {
  String? _ferme;
  DateTime? _mois;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final lignes = etat.depots.where((d) {
      if (_ferme != null && d.fermeId != _ferme) return false;
      if (_mois != null &&
          (d.date == null ||
              d.date!.year != _mois!.year ||
              d.date!.month != _mois!.month)) return false;
      return true;
    }).toList();

    final envoyesParAdmin = lignes
        .where((d) => d.roleAuteur == Role.admin && d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    final remontes = lignes
        .where((d) => d.roleAuteur != Role.admin && d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    final attente = lignes
        .where((d) => Statut.enAttente(d.statut))
        .fold<int>(0, (s, d) => s + d.montant);

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
                  libelle: etat.estAdmin ? 'Envoyés aux fermes' : 'Reçus de l’admin',
                  valeur: gnfCourt(envoyesParAdmin),
                  couleur: Palette.bleu,
                  icone: Icons.south_west_rounded),
              CarteChiffre(
                  libelle: 'Remontés à l’admin',
                  valeur: gnfCourt(remontes),
                  couleur: Palette.vert,
                  icone: Icons.north_east_rounded),
              CarteChiffre(
                  libelle: 'En attente',
                  valeur: gnfCourt(attente),
                  complement: '${lignes.where((d) => Statut.enAttente(d.statut)).length} dépôt(s)',
                  couleur: Palette.orFonce,
                  icone: Icons.hourglass_top_rounded),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            if (lignes.isEmpty)
              Bloc(
                  enfant: Vide('Aucun dépôt enregistré',
                      icone: Icons.account_balance_outlined,
                      action: 'Enregistrer un dépôt',
                      auClic: () => formulaireDepot(context)))
            else
              for (final d in lignes) _carte(context, etat, d),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Palette.bleu,
        foregroundColor: Colors.white,
        onPressed: () => formulaireDepot(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau dépôt'),
      ),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
    final maintenant = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        if (etat.estAdmin) ...[
          PopupMenuButton<String?>(
            onSelected: (v) => setState(() => _ferme = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Toutes les fermes')),
              for (final f in etat.fermes)
                PopupMenuItem(value: f.id, child: Text(f.nom)),
            ],
            child: Chip(
              avatar: const Icon(Icons.holiday_village_outlined, size: 17),
              label: Text(
                  _ferme == null ? 'Toutes les fermes' : etat.nomFerme(_ferme)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        PopupMenuButton<DateTime?>(
          onSelected: (v) => setState(() => _mois = v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: null, child: Text('Tous les mois')),
            for (var i = 0; i < 12; i++)
              PopupMenuItem(
                value: DateTime(maintenant.year, maintenant.month - i),
                child: Text(
                    moisAnnee(DateTime(maintenant.year, maintenant.month - i))),
              ),
          ],
          child: Chip(
            avatar: const Icon(Icons.calendar_month_outlined, size: 17),
            label: Text(_mois == null ? 'Tous les mois' : moisAnnee(_mois)),
          ),
        ),
        if (_ferme != null || _mois != null) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Effacer'),
            onPressed: () => setState(() {
              _ferme = null;
              _mois = null;
            }),
          ),
        ],
      ]),
    );
  }

  Widget _carte(BuildContext context, Etat etat, Depot d) {
    final versLaFerme = d.roleAuteur == Role.admin;
    final couleur = versLaFerme ? Palette.bleu : Palette.vert;
    final peutDecider = Statut.enAttente(d.statut) &&
        ((etat.estGerant && d.statut == Statut.attenteGerant) ||
            (etat.estAdmin && d.statut == Statut.attenteAdmin));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: couleur.withValues(alpha: 0.13),
                  child: Icon(
                      versLaFerme
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: couleur,
                      size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gnf(d.montant),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                          '${jour(d.date)} · ${etat.nomFerme(d.fermeId)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                PuceStatut(d.statut),
              ]),
              const SizedBox(height: 10),
              LigneInfo(
                  'Origine',
                  versLaFerme
                      ? '🏦 Envoyé par l’administration'
                      : '${Role.emoji(d.roleAuteur)} ${etat.nomPersonne(d.auteurId)}'),
              if (d.reference.isNotEmpty) LigneInfo('N° de reçu', d.reference),
              if (d.motif.isNotEmpty) LigneInfo('Motif', d.motif),
              if (d.motifRejet.isNotEmpty)
                LigneInfo('Motif du rejet', d.motifRejet),
              if (d.fichiers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    for (var i = 0; i < d.fichiers.length; i++)
                      ActionChip(
                        avatar:
                            const Icon(Icons.receipt_long_rounded, size: 16),
                        label: Text('Reçu ${i + 1}'),
                        onPressed: () => _ouvrir(context, d.fichiers[i]),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
          if (peutDecider) ...[
            const Divider(height: 1),
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: Palette.rouge,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const RoundedRectangleBorder()),
                  onPressed: () => _decider(context, etat, d, false),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Rejeter'),
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
                  onPressed: () => _decider(context, etat, d, true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Valider'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _decider(
      BuildContext context, Etat etat, Depot d, bool accepte) async {
    String? motif;
    if (!accepte) {
      motif = await demanderTexte(context,
          titre: 'Motif du rejet',
          indice: 'Reçu illisible, montant incorrect…',
          ok: 'Rejeter');
      if (motif == null || !context.mounted) return;
    }
    final e = await etat.agir(() => accepte
        ? Api.valider('depots', [d.id], roleValidateur: etat.role)
        : Api.rejeter('depots', [d.id], motif!.isEmpty ? 'Rejeté' : motif));
    if (context.mounted) {
      message(context, e ?? (accepte ? 'Dépôt validé' : 'Dépôt rejeté'),
          erreur: e != null);
    }
  }

  Future<void> _ouvrir(BuildContext context, String url) async {
    if (url.toLowerCase().endsWith('.pdf')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBar(
            title: const Text('Reçu justificatif'),
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
                        child: Vide('Impossible d’afficher ce fichier',
                            icone: Icons.broken_image_outlined),
                      )),
            ),
          ),
        ]),
      ),
    );
  }
}
