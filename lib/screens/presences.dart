import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';

/// Qui est au travail en ce moment, et l'historique des pointages.
class EcranPresences extends StatefulWidget {
  const EcranPresences({super.key});

  @override
  State<EcranPresences> createState() => _EcranPresencesState();
}

class _EcranPresencesState extends State<EcranPresences> {
  Timer? _horloge;
  String? _ferme;
  DateTime? _jour;

  @override
  void initState() {
    super.initState();
    _horloge = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
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

    // « En ligne maintenant » ne concerne que les gens que j'ai le droit de voir.
    final enLigne = etat.pointagesEnCours.where((p) {
      if (!etat.estAdmin && p.fermeId != etat.maFermeId) return false;
      if (_ferme != null && p.fermeId != _ferme) return false;
      return true;
    }).toList();

    final historique = etat.pointages.where((p) {
      if (_ferme != null && p.fermeId != _ferme) return false;
      if (_jour != null && iso(p.debut.toLocal()) != iso(_jour!)) return false;
      return true;
    }).toList();

    final totalHeures =
        historique.fold<int>(0, (s, p) => s + (p.duree ?? 0));

    return RefreshIndicator(
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          _filtres(context, etat),
          const SizedBox(height: 14),
          GrilleChiffres([
            CarteChiffre(
                libelle: 'En ligne maintenant',
                valeur: '${enLigne.length}',
                complement: 'personne(s) au travail',
                couleur: Palette.vertMoyen,
                icone: Icons.sensors_rounded),
            CarteChiffre(
                libelle: 'Heures cumulées',
                valeur: duree(totalHeures),
                complement: '${historique.length} pointage(s)',
                couleur: Palette.bleu,
                icone: Icons.timelapse_rounded),
          ], largeurMin: 150),
          const TitreSection('En ligne maintenant', emoji: '🟢'),
          Bloc(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            enfant: enLigne.isEmpty
                ? const Vide('Personne n’est pointé en ce moment',
                    icone: Icons.nightlight_round)
                : Column(children: [
                    for (final p in enLigne) _ligneEnLigne(context, etat, p),
                  ]),
          ),
          const TitreSection('Historique des pointages', emoji: '📋'),
          if (historique.isEmpty)
            const Bloc(
                enfant: Vide('Aucun pointage pour ce filtre',
                    icone: Icons.history_rounded))
          else
            Bloc(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              enfant: Column(children: [
                for (final p in historique.take(80))
                  ListTile(
                    dense: true,
                    leading: Pastille(etat.nomPersonne(p.profilId),
                        photoUrl: etat.personne(p.profilId)?.photoUrl,
                        taille: 36),
                    title: Text(etat.nomPersonne(p.profilId),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${jour(p.debut)} · ${heure(p.debut)} → '
                        '${p.fin == null ? 'en cours' : heure(p.fin)}'
                        '${etat.estAdmin ? ' · ${etat.nomFerme(p.fermeId)}' : ''}'),
                    trailing: Text(
                        p.enCours ? 'En cours' : duree(p.duree),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: p.enCours ? Palette.vertMoyen : null)),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _ligneEnLigne(BuildContext context, Etat etat, Pointage p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Stack(children: [
          Pastille(etat.nomPersonne(p.profilId),
              photoUrl: etat.personne(p.profilId)?.photoUrl, taille: 42),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.vertClair,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etat.nomPersonne(p.profilId),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                  'Arrivé à ${heure(p.debut)}'
                  '${etat.estAdmin ? ' · ${etat.nomFerme(p.fermeId)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Etiquette(duree(p.dureeSecondes),
            couleur: Palette.vertMoyen, icone: Icons.timer_outlined),
      ]),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
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
        ActionChip(
          avatar: const Icon(Icons.calendar_month_outlined, size: 17),
          label: Text(_jour == null ? 'Tous les jours' : jour(_jour)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _jour ?? aujourdhui(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              locale: const Locale('fr', 'FR'),
            );
            if (d != null) setState(() => _jour = d);
          },
        ),
        if (_ferme != null || _jour != null) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Effacer'),
            onPressed: () => setState(() {
              _ferme = null;
              _jour = null;
            }),
          ),
        ],
      ]),
    );
  }
}
