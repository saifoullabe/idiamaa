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

/// Ce que les fermiers et les gérants font remonter en image, rangé par jour.
/// Les images vivent dans Supabase Storage, pas dans la base.
class EcranPhotos extends StatefulWidget {
  const EcranPhotos({super.key});

  @override
  State<EcranPhotos> createState() => _EcranPhotosState();
}

class _EcranPhotosState extends State<EcranPhotos> {
  String? _ferme;
  String? _auteur;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final lignes = etat.photos.where((p) {
      if (_ferme != null && p.fermeId != _ferme) return false;
      if (_auteur != null && p.auteurId != _auteur) return false;
      return true;
    }).toList();

    // Rangées par journée : c'est ainsi qu'on les cherche, pas une par une.
    final parJour = <String, List<Photo>>{};
    for (final p in lignes) {
      parJour.putIfAbsent(iso(p.date ?? aujourdhui()), () => []).add(p);
    }
    final jours = parJour.keys.toList()..sort((a, b) => b.compareTo(a));

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
                  libelle: 'Photos reçues',
                  valeur: '${lignes.length}',
                  complement: '${jours.length} journée(s)',
                  couleur: Palette.bleu,
                  icone: Icons.photo_library_rounded),
              CarteChiffre(
                  libelle: 'Aujourd’hui',
                  valeur:
                      '${parJour[iso(aujourdhui())]?.length ?? 0}',
                  couleur: Palette.vert,
                  icone: Icons.today_rounded),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            if (jours.isEmpty)
              Bloc(
                  enfant: Vide(
                      etat.estAdmin
                          ? 'Aucune photo reçue des fermes'
                          : 'Vous n’avez encore envoyé aucune photo',
                      icone: Icons.photo_camera_outlined,
                      action: etat.estAdmin ? null : 'Envoyer une photo',
                      auClic: etat.estAdmin
                          ? null
                          : () => formulairePhoto(context)))
            else
              for (final j in jours) _journee(context, etat, j, parJour[j]!),
          ],
        ),
      ),
      floatingActionButton: etat.estAdmin
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Palette.bleu,
              foregroundColor: Colors.white,
              onPressed: () => formulairePhoto(context),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Envoyer'),
            ),
    );
  }

  Widget _journee(
      BuildContext context, Etat etat, String jourIso, List<Photo> lot) {
    // Les photos envoyées ensemble partagent la même note : on les regroupe
    // pour ne pas répéter dix fois la même phrase.
    final parNote = <String, List<Photo>>{};
    for (final p in lot) {
      parNote.putIfAbsent('${p.auteurId}|${p.note}', () => []).add(p);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Bloc(
        enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.event_rounded, size: 16, color: Palette.gris),
                const SizedBox(width: 8),
                Text(jour(DateTime.parse(jourIso)),
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Etiquette('${lot.length} photo(s)', couleur: Palette.bleu),
              ]),
              const Divider(height: 20),
              for (final groupe in parNote.values) ...[
                Row(children: [
                  Pastille(etat.nomPersonne(groupe.first.auteurId),
                      photoUrl: etat.personne(groupe.first.auteurId)?.photoUrl,
                      taille: 30,
                      couleur: Palette.duRole(groupe.first.roleAuteur)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                        '${etat.nomPersonne(groupe.first.auteurId)}'
                        '${etat.estAdmin ? ' · ${etat.nomFerme(groupe.first.fermeId)}' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(heure(groupe.first.creeLe),
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
                if (groupe.first.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 39),
                    child: Text(groupe.first.note,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                if (groupe.first.batimentId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 39),
                    child: Text(
                        '🏗️  ${etat.batiment(groupe.first.batimentId)?.nom ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 10),
                GaleriePhotos(groupe.map((p) => p.url).toList()),
                if (etat.estAdmin || etat.estGerant ||
                    groupe.first.auteurId == etat.moi!.id)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).hintColor),
                      onPressed: () => _supprimer(context, etat, groupe),
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('Supprimer',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ]),
      ),
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
        PopupMenuButton<String?>(
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
        if (_ferme != null || _auteur != null) ...[
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 17),
            label: const Text('Effacer'),
            onPressed: () => setState(() {
              _ferme = null;
              _auteur = null;
            }),
          ),
        ],
      ]),
    );
  }

  Future<void> _supprimer(
      BuildContext context, Etat etat, List<Photo> groupe) async {
    final ok = await confirmer(context,
        titre: groupe.length > 1
            ? 'Supprimer ces ${groupe.length} photos ?'
            : 'Supprimer cette photo ?',
        texte: 'Elles seront définitivement effacées.',
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() async {
      for (final p in groupe) {
        await Api.supprimerPhoto(p.id);
      }
    });
    if (context.mounted) {
      message(context, e ?? 'Photo(s) supprimée(s)', erreur: e != null);
    }
  }
}
