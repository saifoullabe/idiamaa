import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/facture.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import 'formulaires.dart';

/// Les revendeurs de la ferme et tout ce qu'ils ont acheté.
/// Le gérant tient les fiches ; l'administrateur voit celles de toutes
/// ses fermes. Chaque achat porte un numéro de facture donné par la
/// base, et chaque facture se retire en PDF.
class EcranClients extends StatefulWidget {
  const EcranClients({super.key});

  @override
  State<EcranClients> createState() => _EcranClientsState();
}

class _EcranClientsState extends State<EcranClients> {
  String? _ferme;
  String _cherche = '';
  bool _masquerInactifs = true;
  final _ouverts = <String>{};

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final recherche = _cherche.trim().toLowerCase();
    final clients = etat.clients.where((c) {
      if (_ferme != null && c.fermeId != _ferme) return false;
      if (_masquerInactifs && !c.actif) return false;
      if (recherche.isEmpty) return true;
      return c.nom.toLowerCase().contains(recherche) ||
          c.telephone.contains(recherche) ||
          c.adresse.toLowerCase().contains(recherche);
    }).toList();

    final visibles = clients.map((c) => c.id).toSet();
    final ventes =
        etat.ventes.where((v) => visibles.contains(v.clientId)).toList();
    final total = ventes.fold<int>(0, (s, v) => s + v.montant);
    final impaye =
        ventes.where((v) => !v.paye).fold<int>(0, (s, v) => s + v.montant);
    final alveoles = ventes.fold<int>(0, (s, v) => s + v.nbAlveoles);

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
                  libelle: 'Chiffre d’affaires',
                  valeur: gnfCourt(total),
                  complement: '${ventes.length} achat(s)',
                  couleur: Palette.vert,
                  icone: Icons.trending_up_rounded),
              CarteChiffre(
                  libelle: 'Alvéoles vendues',
                  valeur: nb(alveoles),
                  complement: '${nb(alveoles * 30)} œufs',
                  couleur: Palette.or,
                  icone: Icons.egg_outlined),
              CarteChiffre(
                  libelle: 'Reste à encaisser',
                  valeur: gnfCourt(impaye),
                  complement: impaye == 0
                      ? 'tout est payé'
                      : '${ventes.where((v) => !v.paye).length} facture(s)',
                  couleur: impaye == 0 ? Palette.gris : Palette.rouge,
                  icone: Icons.hourglass_bottom_rounded),
              CarteChiffre(
                  libelle: 'Revendeurs',
                  valeur: '${clients.length}',
                  complement: 'fiches ouvertes',
                  couleur: Palette.bleu,
                  icone: Icons.storefront_outlined),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            if (clients.isEmpty)
              Bloc(
                  enfant: Vide(
                      recherche.isNotEmpty
                          ? 'Aucun revendeur ne correspond à cette recherche'
                          : 'Aucune fiche revendeur pour l’instant',
                      icone: Icons.storefront_outlined,
                      action: etat.estFermier ? null : 'Créer une fiche',
                      auClic: () => formulaireClient(context)))
            else
              for (final c in clients) _carte(context, etat, c),
          ],
        ),
      ),
      floatingActionButton: etat.estFermier
          ? null
          : FloatingActionButton.extended(
              onPressed: () => formulaireClient(context),
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Nouveau client'),
            ),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) => Bloc(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        enfant: Column(children: [
          TextField(
            onChanged: (v) => setState(() => _cherche = v),
            decoration: InputDecoration(
              hintText: 'Chercher un nom, un téléphone…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              suffixIcon: _cherche.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _cherche = ''),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (etat.estAdmin && etat.fermes.length > 1) ...[
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _ferme,
                  isDense: true,
                  decoration:
                      const InputDecoration(labelText: 'Ferme', isDense: true),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Toutes les fermes')),
                    for (final f in etat.fermes)
                      DropdownMenuItem(value: f.id, child: Text(f.nom)),
                  ],
                  onChanged: (v) => setState(() => _ferme = v),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(children: [
                Checkbox(
                  value: _masquerInactifs,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) =>
                      setState(() => _masquerInactifs = v ?? true),
                ),
                const Flexible(
                    child: Text('Masquer les fiches fermées',
                        style: TextStyle(fontSize: 12.5))),
              ]),
            ),
          ]),
        ]),
      );

  Widget _carte(BuildContext context, Etat etat, Client c) {
    final achats = etat.ventes.where((v) => v.clientId == c.id).toList()
      ..sort((a, b) =>
          (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    final total = achats.fold<int>(0, (s, v) => s + v.montant);
    final impaye =
        achats.where((v) => !v.paye).fold<int>(0, (s, v) => s + v.montant);
    final alveoles = achats.fold<int>(0, (s, v) => s + v.nbAlveoles);
    final ouvert = _ouverts.contains(c.id);
    final dernier = achats.isEmpty ? null : achats.first.date;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Bloc(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        auClic: () => setState(
            () => ouvert ? _ouverts.remove(c.id) : _ouverts.add(c.id)),
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pastille(c.nom, couleur: c.actif ? Palette.vert : Palette.gris),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nom,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                        [
                          c.type,
                          if (c.telephone.isNotEmpty) c.telephone,
                          if (etat.estAdmin) etat.nomFerme(c.fermeId),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(gnfCourt(total),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Palette.vert)),
              Text('${achats.length} achat(s)',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            Icon(ouvert ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: Theme.of(context).hintColor),
          ]),
          if (impaye > 0 || !c.actif || dernier != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 7, children: [
              if (impaye > 0)
                Etiquette('${gnfCourt(impaye)} impayés',
                    couleur: Palette.rouge, icone: Icons.warning_amber_rounded),
              if (!c.actif)
                const Etiquette('Fiche fermée',
                    couleur: Palette.gris, icone: Icons.archive_outlined),
              if (dernier != null)
                Etiquette('Dernier achat ${jourMois(dernier)}',
                    couleur: Palette.bleu, icone: Icons.event_outlined),
              if (alveoles > 0)
                Etiquette('${nb(alveoles)} alvéoles',
                    couleur: Palette.or, icone: Icons.egg_outlined),
            ]),
          ],
          if (ouvert) ...[
            const Divider(height: 24),
            if (c.adresse.isNotEmpty)
              LigneInfo('Adresse', c.adresse, icone: Icons.place_outlined),
            if (c.telephone2.isNotEmpty)
              LigneInfo('Autre téléphone', c.telephone2,
                  icone: Icons.phone_outlined),
            if (c.note.isNotEmpty)
              LigneInfo('Note', c.note, icone: Icons.sticky_note_2_outlined),
            const SizedBox(height: 6),
            if (achats.isEmpty)
              const Vide('Aucun achat enregistré pour ce revendeur',
                  icone: Icons.receipt_long_outlined)
            else ...[
              const TitreSection('Historique des achats'),
              for (final v in achats) _achat(context, etat, c, v),
            ],
            const SizedBox(height: 8),
            _actions(context, etat, c, achats),
          ],
        ]),
      ),
    );
  }

  Widget _achat(BuildContext context, Etat etat, Client c, Vente v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Palette.beige,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(v.reference,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(width: 8),
              Etiquette(v.paye ? 'Payé' : 'À encaisser',
                  couleur: v.paye ? Palette.vert : Palette.rouge),
            ]),
            const SizedBox(height: 5),
            Text(
                '${jourMois(v.date)} · ${nb(v.nbAlveoles)} alvéoles '
                '× ${gnf(v.prixAlveole)}',
                style: Theme.of(context).textTheme.bodySmall),
            Text('${nb(v.oeufs)} œufs',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11)),
            if (v.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(v.note,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(gnf(v.montant),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Facture PDF',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
              color: Palette.vert,
              onPressed: () => _facture(context, etat, c, v),
            ),
            if (!etat.estFermier)
              PopupMenuButton<String>(
                tooltip: '',
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
                padding: EdgeInsets.zero,
                onSelected: (choix) => _menuAchat(context, etat, v, choix),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'paiement',
                    child: Text(v.paye
                        ? 'Marquer comme impayé'
                        : 'Marquer comme payé'),
                  ),
                  const PopupMenuItem(
                    value: 'supprimer',
                    child: Text('Supprimer cet achat'),
                  ),
                ],
              ),
          ]),
        ]),
      ]),
    );
  }

  Widget _actions(
      BuildContext context, Etat etat, Client c, List<Vente> achats) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (!etat.estFermier)
        FilledButton.icon(
          onPressed: () => formulaireVente(context, client: c),
          icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
          label: const Text('Nouvel achat'),
        ),
      if (achats.isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => _releve(context, etat, c, achats),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text('Relevé PDF'),
        ),
      if (!etat.estFermier)
        OutlinedButton.icon(
          onPressed: () => formulaireClient(context, client: c),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Modifier'),
        ),
      if (!etat.estFermier)
        TextButton.icon(
          onPressed: () => _fermerFiche(context, etat, c),
          icon: Icon(
              c.actif ? Icons.archive_outlined : Icons.unarchive_outlined,
              size: 18),
          label: Text(c.actif ? 'Fermer la fiche' : 'Rouvrir la fiche'),
        ),
    ]);
  }

  // ── Les papiers ────────────────────────────────────────────────────
  Future<void> _facture(
      BuildContext context, Etat etat, Client c, Vente v) async {
    final f = etat.ferme(c.fermeId);
    final noms = etat.personnes
        .where((p) => p.id == v.auteurId)
        .map((p) => '${p.prenom} ${p.nom}'.trim())
        .where((n) => n.isNotEmpty);
    try {
      await Facture.vente(
        v: v,
        client: c,
        nomFerme: f?.nom ?? 'IDIAMA Agro',
        villeFerme: f?.ville ?? '',
        vendeur: noms.isEmpty ? 'IDIAMA Agro' : noms.first,
      );
    } catch (e) {
      if (context.mounted) {
        message(context, 'Impossible de produire la facture : $e',
            erreur: true);
      }
    }
  }

  Future<void> _releve(
      BuildContext context, Etat etat, Client c, List<Vente> achats) async {
    final f = etat.ferme(c.fermeId);
    try {
      await Facture.releve(
        client: c,
        ventes: achats,
        nomFerme: f?.nom ?? 'IDIAMA Agro',
        villeFerme: f?.ville ?? '',
      );
    } catch (e) {
      if (context.mounted) {
        message(context, 'Impossible de produire le relevé : $e', erreur: true);
      }
    }
  }

  // ── Les changements ────────────────────────────────────────────────
  Future<void> _menuAchat(
      BuildContext context, Etat etat, Vente v, String choix) async {
    if (choix == 'paiement') {
      final erreur =
          await etat.agir(() => Api.majVente(v.id, {'paye': !v.paye}));
      if (!context.mounted) return;
      message(context, erreur ?? (v.paye ? 'Marqué impayé' : 'Marqué payé'),
          erreur: erreur != null);
      return;
    }

    final sur = await confirmer(
      context,
      titre: 'Supprimer l’achat ${v.reference} ?',
      texte: 'La recette de ${gnf(v.montant)} qui va avec sera retirée des '
          'comptes de la ferme. Cette action est définitive.',
      ok: 'Supprimer',
      danger: true,
    );
    if (!sur || !context.mounted) return;
    final erreur = await etat.agir(() => Api.supprimerVente(v.id));
    if (!context.mounted) return;
    message(context, erreur ?? 'Achat supprimé', erreur: erreur != null);
  }

  Future<void> _fermerFiche(BuildContext context, Etat etat, Client c) async {
    if (c.actif) {
      final sur = await confirmer(
        context,
        titre: 'Fermer la fiche de ${c.nom} ?',
        texte: 'Ses achats restent enregistrés et ses factures restent '
            'consultables. La fiche disparaît simplement de la liste.',
        ok: 'Fermer la fiche',
      );
      if (!sur || !context.mounted) return;
    }
    final erreur =
        await etat.agir(() => Api.majClient(c.id, {'actif': !c.actif}));
    if (!context.mounted) return;
    message(context, erreur ?? (c.actif ? 'Fiche fermée' : 'Fiche rouverte'),
        erreur: erreur != null);
  }
}
