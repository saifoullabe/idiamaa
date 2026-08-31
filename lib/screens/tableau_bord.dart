import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/graphiques.dart';
import 'fermes.dart';
import 'formulaires.dart';

class TableauBord extends StatelessWidget {
  const TableauBord({super.key});

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    if (etat.chargement && etat.fermes.isEmpty) return const ChargementPage();

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
        children: switch (etat.role) {
          Role.admin => _admin(context, etat),
          Role.gerant => _gerant(context, etat),
          _ => _fermier(context, etat),
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // ADMINISTRATEUR
  // ══════════════════════════════════════════════════════════════════
  List<Widget> _admin(BuildContext context, Etat etat) {
    final ventes = etat.totalRecettes();
    final depotsRecus = etat.totalDepotsRecus();
    final depenses = etat.totalDepenses();
    final solde = ventes + depotsRecus - depenses;

    return [
      _salutation(context, etat),
      const SizedBox(height: 16),
      if (etat.aValiderAdmin > 0) ...[
        Bandeau(
          titre: '${etat.aValiderAdmin} saisie(s) à valider',
          texte: 'Envoyées par les gérants des fermes.',
          couleur: Palette.orFonce,
          icone: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 14),
      ],
      GrilleChiffres([
        CarteChiffre(
            libelle: 'Ventes validées',
            valeur: gnfCourt(ventes),
            complement: 'Toutes fermes',
            couleur: Palette.vert,
            icone: Icons.trending_up_rounded),
        CarteChiffre(
            libelle: 'Dépôts envoyés',
            valeur: gnfCourt(depotsRecus),
            complement: 'Aux fermes',
            couleur: Palette.bleu,
            icone: Icons.account_balance_rounded),
        CarteChiffre(
            libelle: 'Dépenses',
            valeur: gnfCourt(depenses),
            complement: 'Validées',
            couleur: Palette.rouge,
            icone: Icons.trending_down_rounded),
        CarteChiffre(
            libelle: 'Solde net',
            valeur: gnfCourt(solde),
            complement: 'Entrées − dépenses',
            couleur: solde >= 0 ? Palette.or : Palette.rouge,
            icone: Icons.savings_rounded),
      ]),
      const SizedBox(height: 16),
      Bloc(
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('Recettes et dépenses',
                    style: Theme.of(context).textTheme.titleSmall)),
            Text('6 derniers mois',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 16),
          BarresMensuelles(etat.serieMensuelle()),
        ]),
      ),
      const SizedBox(height: 12),
      _grilleCompteurs(context, [
        ('Fermes', '${etat.fermes.length}', Icons.holiday_village_rounded),
        ('Gérants', '${etat.gerants().length}', Icons.manage_accounts_rounded),
        ('Fermiers', '${etat.fermiers().length}', Icons.agriculture_rounded),
        ('Bâtiments', '${etat.batiments.length}', Icons.warehouse_rounded),
      ]),
      TitreSection('Mes fermes',
          emoji: '🏚️',
          action: TextButton.icon(
            onPressed: () => formulaireFerme(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nouvelle'),
          )),
      if (etat.fermes.isEmpty)
        Bloc(
            enfant: Vide('Aucune ferme enregistrée',
                icone: Icons.holiday_village_outlined,
                action: 'Créer la première ferme',
                auClic: () => formulaireFerme(context)))
      else
        for (final f in etat.fermes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CarteFerme(f),
          ),
      TitreSection('Derniers dépôts', emoji: '💰'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enfant: Column(children: [
          if (etat.depots.isEmpty)
            const Vide('Aucun dépôt', icone: Icons.account_balance_outlined)
          else
            for (final d in etat.depots.take(5))
              _ligneDepot(context, etat, d),
        ]),
      ),
      TitreSection('Signalements ouverts', emoji: '⚠️'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enfant: Column(children: [
          if (etat.signalements.where((s) => s.ouvert).isEmpty)
            const Vide('Aucun signalement en cours',
                icone: Icons.check_circle_outline_rounded)
          else
            for (final s in etat.signalements.where((s) => s.ouvert).take(6))
              _ligneSignalement(context, etat, s),
        ]),
      ),
    ];
  }

  // ══════════════════════════════════════════════════════════════════
  // GÉRANT
  // ══════════════════════════════════════════════════════════════════
  List<Widget> _gerant(BuildContext context, Etat etat) {
    final fid = etat.maFermeId;
    final ventes = etat.totalRecettes(fermeId: fid);
    final depots = etat.totalDepotsRecus(fermeId: fid);
    final depenses = etat.totalDepenses(fermeId: fid);
    final solde = ventes + depots - depenses;
    final bats = etat.batimentsDe(fid);
    final prodJour = etat.productions
        .where((p) => p.date != null && iso(p.date!) == iso(aujourdhui()))
        .toList();

    return [
      _salutation(context, etat),
      const SizedBox(height: 16),
      if (etat.aValiderGerant > 0) ...[
        Bandeau(
          titre: '${etat.aValiderGerant} saisie(s) en attente',
          texte:
              'Vos fermiers attendent votre validation pour que ça compte.',
          couleur: Palette.orFonce,
          icone: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 14),
      ],
      GrilleChiffres([
        CarteChiffre(
            libelle: 'Ventes ferme',
            valeur: gnfCourt(ventes),
            complement:
                '${gnfCourt(etat.recettes.where((r) => Statut.enAttente(r.statut)).fold<int>(0, (s, r) => s + r.montant))} en attente',
            couleur: Palette.vert,
            icone: Icons.trending_up_rounded),
        CarteChiffre(
            libelle: 'Dépôts reçus',
            valeur: gnfCourt(depots),
            complement: 'De l’administration',
            couleur: Palette.bleu,
            icone: Icons.account_balance_rounded),
        CarteChiffre(
            libelle: 'Dépenses',
            valeur: gnfCourt(depenses),
            complement: 'Validées',
            couleur: Palette.rouge,
            icone: Icons.trending_down_rounded),
        CarteChiffre(
            libelle: 'Solde net',
            valeur: gnfCourt(solde),
            complement: 'Ventes + dépôts − dépenses',
            couleur: solde >= 0 ? Palette.or : Palette.rouge,
            icone: Icons.savings_rounded),
      ]),
      const SizedBox(height: 16),
      Bloc(
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('Œufs ramassés',
                    style: Theme.of(context).textTheme.titleSmall)),
            Text('7 derniers jours',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 14),
          CourbeProduction(etat.serieProduction(fermeId: fid)),
        ]),
      ),
      TitreSection('Production du jour', emoji: '🥚'),
      Bloc(
        enfant: bats.isEmpty
            ? const Vide('Aucun bâtiment sur cette ferme',
                icone: Icons.warehouse_outlined)
            : Column(children: [
                for (final b in bats)
                  _ligneBatimentJour(context, b, prodJour),
                const Divider(height: 22),
                _totalJour(context, prodJour),
              ]),
      ),
      TitreSection('Signalements des fermiers', emoji: '⚠️'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enfant: Column(children: [
          if (etat.signalements.where((s) => s.ouvert).isEmpty)
            const Vide('Aucun signalement en cours',
                icone: Icons.check_circle_outline_rounded)
          else
            for (final s in etat.signalements.where((s) => s.ouvert).take(6))
              _ligneSignalement(context, etat, s),
        ]),
      ),
      TitreSection('Derniers rapports reçus', emoji: '📋'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enfant: Column(children: [
          if (etat.rapports.isEmpty)
            const Vide('Aucun rapport reçu',
                icone: Icons.description_outlined)
          else
            for (final r in etat.rapports.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Text('📋', style: TextStyle(fontSize: 20)),
                title: Text(r.titre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle:
                    Text('${etat.nomPersonne(r.auteurId)} · ${jour(r.date)}'),
              ),
        ]),
      ),
    ];
  }

  // ══════════════════════════════════════════════════════════════════
  // FERMIER
  // ══════════════════════════════════════════════════════════════════
  List<Widget> _fermier(BuildContext context, Etat etat) {
    final moi = etat.moi!;
    final jourCourant = aujourdhui();
    // La production du jour de la ferme : une seule ligne par bâtiment,
    // qu'elle ait été saisie par le fermier ou corrigée par le gérant.
    final maProd = etat.productions
        .where((p) => p.date != null && iso(p.date!) == iso(jourCourant))
        .toList();
    final mesVentes = etat.recettes
        .where((r) => r.auteurId == moi.id && r.statut == Statut.valide)
        .fold<int>(0, (s, r) => s + r.montant);
    final mesDepenses = etat.depenses
        .where((d) => d.auteurId == moi.id && d.statut == Statut.valide)
        .fold<int>(0, (s, d) => s + d.montant);
    final bats = etat.batimentsDe(etat.maFermeId);

    return [
      _salutation(context, etat),
      const SizedBox(height: 16),
      _carteEnLigne(context, etat),
      const SizedBox(height: 14),
      GrilleChiffres([
        CarteChiffre(
            libelle: 'Œufs aujourd’hui',
            valeur: nb(maProd.fold<int>(0, (s, p) => s + p.oeufs)),
            complement:
                '${maProd.fold<int>(0, (s, p) => s + p.nbAlveoles)} alvéoles',
            couleur: Palette.bleu,
            icone: Icons.egg_rounded),
        CarteChiffre(
            libelle: 'Valeur du jour',
            valeur: gnfCourt(maProd.fold<int>(0, (s, p) => s + p.valeur)),
            couleur: Palette.or,
            icone: Icons.sell_rounded),
        CarteChiffre(
            libelle: 'Mes ventes',
            valeur: gnfCourt(mesVentes),
            complement: 'Validées',
            couleur: Palette.vert,
            icone: Icons.payments_rounded),
        CarteChiffre(
            libelle: 'Mes dépenses',
            valeur: gnfCourt(mesDepenses),
            complement: 'Validées',
            couleur: Palette.rouge,
            icone: Icons.receipt_long_rounded),
      ]),
      const SizedBox(height: 16),
      Bloc(
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('Ma production',
                    style: Theme.of(context).textTheme.titleSmall)),
            Text('7 derniers jours',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 14),
          CourbeProduction(etat.serieProduction(fermeId: etat.maFermeId)),
        ]),
      ),
      TitreSection('Ma saisie du jour', emoji: '🥚'),
      Bloc(
        enfant: bats.isEmpty
            ? const Vide('Aucun bâtiment sur votre ferme',
                icone: Icons.warehouse_outlined)
            : Column(children: [
                for (final b in bats) _ligneBatimentJour(context, b, maProd),
                const Divider(height: 22),
                _totalJour(context, maProd),
              ]),
      ),
      TitreSection('Mes stocks', emoji: '📦'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        enfant: Column(children: [
          if (etat.stocks.isEmpty)
            const Vide('Aucun stock enregistré',
                icone: Icons.inventory_2_outlined)
          else
            for (final s in etat.stocks.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Text(s.nom,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Etiquette('${nb(s.quantite)} ${s.unite}',
                      couleur: s.critique
                          ? Palette.rouge
                          : (s.faible ? Palette.orFonce : Palette.vert)),
                ]),
              ),
        ]),
      ),
      TitreSection('Mes dernières activités', emoji: '📋'),
      Bloc(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        enfant: Column(children: [
          ..._activitesRecentes(context, etat),
        ]),
      ),
    ];
  }

  // ── Briques partagées ────────────────────────────────────────────
  Widget _salutation(BuildContext context, Etat etat) {
    final h = DateTime.now().hour;
    final bonjour = h < 12
        ? 'Bonjour'
        : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: Palette.degradeRole(etat.role),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$bonjour,',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13)),
              const SizedBox(height: 3),
              Text(etat.moi?.prenom.isNotEmpty == true
                  ? etat.moi!.prenom
                  : (etat.moi?.nomComplet ?? ''),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(jourLong(aujourdhui()),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11.5)),
            ],
          ),
        ),
        Text(Role.emoji(etat.role), style: const TextStyle(fontSize: 36)),
      ]),
    );
  }

  Widget _grilleCompteurs(
      BuildContext context, List<(String, String, IconData)> items) {
    return Bloc(
      enfant: Row(
        children: [
          for (final (libelle, valeur, icone) in items)
            Expanded(
              child: Column(children: [
                Icon(icone, size: 19, color: Theme.of(context).hintColor),
                const SizedBox(height: 7),
                Text(valeur,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(libelle,
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _carteEnLigne(BuildContext context, Etat etat) {
    final enLigne = etat.enLigne;
    final couleur = enLigne ? Palette.vertMoyen : Palette.gris;
    return Bloc(
      fond: couleur.withValues(alpha: 0.09),
      bordure: couleur.withValues(alpha: 0.3),
      enfant: Row(children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: couleur,
            boxShadow: enLigne
                ? [BoxShadow(color: couleur.withValues(alpha: 0.4), blurRadius: 10)]
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(enLigne ? 'En ligne — au travail' : 'Hors ligne',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: couleur)),
              const SizedBox(height: 2),
              Text(
                  enLigne
                      ? 'Arrivée pointée à ${heure(etat.monPointage!.debut)}'
                      : 'Allez sur Pointage pour marquer votre arrivée',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _ligneBatimentJour(
      BuildContext context, Batiment b, List<Production> prod) {
    final p = prod.cast<Production?>().firstWhere(
        (x) => x?.batimentId == b.id,
        orElse: () => null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.nom,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text('${b.type} · ${nb(b.nbPoules)} poules',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: Text(p == null ? '—' : '${p.nbAlveoles}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          flex: 2,
          child: Text(p == null ? '—' : '${nb(p.oeufs)} 🥚',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Palette.vert)),
        ),
        if (p != null) ...[
          const SizedBox(width: 8),
          PuceStatut(p.statut, compact: true),
        ],
      ]),
    );
  }

  Widget _totalJour(BuildContext context, List<Production> prod) {
    final oeufs = prod.fold<int>(0, (s, p) => s + p.oeufs);
    final valeur = prod.fold<int>(0, (s, p) => s + p.valeur);
    return Row(children: [
      Expanded(
        child: Text('Total du jour',
            style: Theme.of(context).textTheme.titleSmall),
      ),
      Text('${nb(oeufs)} 🥚   ',
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: Palette.vert)),
      Text(gnf(valeur),
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: Palette.orFonce)),
    ]);
  }

  Widget _ligneDepot(BuildContext context, Etat etat, Depot d) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Palette.bleu.withValues(alpha: 0.13),
        child: const Icon(Icons.account_balance_rounded,
            color: Palette.bleu, size: 19),
      ),
      title: Text(gnf(d.montant),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
          '${etat.nomFerme(d.fermeId)} · ${jour(d.date)}'
          '${d.motif.isEmpty ? '' : ' · ${d.motif}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: PuceStatut(d.statut, compact: true),
    );
  }

  Widget _ligneSignalement(BuildContext context, Etat etat, Signalement s) {
    final c = couleurPriorite(s.priorite);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: c.withValues(alpha: 0.13),
        child: Icon(Icons.warning_amber_rounded, color: c, size: 19),
      ),
      title: Text(s.titre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${etat.nomFerme(s.fermeId)} · ${jour(s.date)}'),
      trailing: Etiquette(s.priorite, couleur: c),
    );
  }

  List<Widget> _activitesRecentes(BuildContext context, Etat etat) {
    final moi = etat.moi!.id;
    final elements = <(DateTime, String, String, IconData, Color)>[
      for (final r in etat.rapports.where((r) => r.auteurId == moi))
        (r.date ?? DateTime.now(), r.titre, 'Rapport', Icons.description_rounded,
            Palette.bleu),
      for (final s in etat.signalements.where((s) => s.auteurId == moi))
        (s.date ?? DateTime.now(), s.titre, 'Signalement',
            Icons.warning_amber_rounded, Palette.orFonce),
      for (final r in etat.recettes.where((r) => r.auteurId == moi))
        (r.date ?? DateTime.now(), '${r.produit} — ${gnf(r.montant)}',
            'Recette', Icons.payments_rounded, Palette.vert),
      for (final d in etat.depenses.where((d) => d.auteurId == moi))
        (d.date ?? DateTime.now(), '${d.article} — ${gnf(d.montant)}',
            'Dépense', Icons.receipt_long_rounded, Palette.rouge),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    if (elements.isEmpty) {
      return [const Vide('Aucune activité pour le moment')];
    }
    return [
      for (final (date, titre, genre, icone, couleur) in elements.take(8))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: couleur.withValues(alpha: 0.13),
            child: Icon(icone, color: couleur, size: 18),
          ),
          title: Text(titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$genre · ${jour(date)}'),
        ),
    ];
  }
}
