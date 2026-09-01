import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/localisation.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';

/// L'historique des sorties de zone. Quand un fermier quitte sa ferme
/// alors qu'il est en ligne, la base le met hors ligne, note la sortie
/// et continue à enregistrer sa position pendant deux heures. Cet écran
/// est le seul endroit où ce chemin se relit.
class EcranItineraire extends StatefulWidget {
  const EcranItineraire({super.key});

  @override
  State<EcranItineraire> createState() => _EcranItineraireState();
}

class _EcranItineraireState extends State<EcranItineraire> {
  String? _ferme;
  String? _personne;
  final _ouverts = <String>{};

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    final sorties = etat.sorties.where((s) {
      if (_ferme != null && s.fermeId != _ferme) return false;
      if (_personne != null && s.profilId != _personne) return false;
      return true;
    }).toList();

    final nouvelles = sorties.where((s) => !s.vuParAdmin).length;
    final aujourdHui = sorties.where((s) {
      final m = s.moment?.toLocal();
      if (m == null) return false;
      final n = DateTime.now();
      return m.year == n.year && m.month == n.month && m.day == n.day;
    }).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Bandeau(
              titre: 'Le suivi s’arrête au bout de deux heures',
              texte: 'Quand quelqu’un quitte sa ferme, sa position continue '
                  'd’être enregistrée pendant deux heures, puis le suivi '
                  's’arrête de lui-même. En dehors du pointage, personne '
                  'n’est suivi.',
              couleur: Palette.bleu,
              icone: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 14),
            _filtres(context, etat),
            const SizedBox(height: 14),
            GrilleChiffres([
              CarteChiffre(
                  libelle: 'Sorties non vues',
                  valeur: '$nouvelles',
                  complement: nouvelles == 0 ? 'rien de nouveau' : 'à regarder',
                  couleur: nouvelles == 0 ? Palette.gris : Palette.orFonce,
                  icone: Icons.notifications_active_rounded),
              CarteChiffre(
                  libelle: 'Aujourd’hui',
                  valeur: '$aujourdHui',
                  complement: 'sortie(s) de zone',
                  couleur: Palette.vert,
                  icone: Icons.today_rounded),
            ], largeurMin: 150),
            const SizedBox(height: 18),
            if (sorties.isEmpty)
              const Bloc(
                  enfant: Vide(
                      'Personne n’a quitté sa ferme pendant un pointage',
                      icone: Icons.route_outlined))
            else
              for (final s in sorties) _carte(context, etat, s),
          ],
        ),
      ),
    );
  }

  Widget _filtres(BuildContext context, Etat etat) {
    final concernes = etat.personnes
        .where((p) => etat.sorties.any((s) => s.profilId == p.id))
        .toList();
    if (etat.fermes.length < 2 && concernes.length < 2) {
      return const SizedBox.shrink();
    }
    return Bloc(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      enfant: Row(children: [
        if (etat.fermes.length > 1) ...[
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _ferme,
              isDense: true,
              decoration:
                  const InputDecoration(labelText: 'Ferme', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final f in etat.fermes)
                  DropdownMenuItem(value: f.id, child: Text(f.nom)),
              ],
              onChanged: (v) => setState(() => _ferme = v),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (concernes.length > 1)
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _personne,
              isDense: true,
              decoration:
                  const InputDecoration(labelText: 'Personne', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final p in concernes)
                  DropdownMenuItem(value: p.id, child: Text(p.nomComplet)),
              ],
              onChanged: (v) => setState(() => _personne = v),
            ),
          ),
      ]),
    );
  }

  Widget _carte(BuildContext context, Etat etat, SortieZone s) {
    final qui = etat.personnes
        .cast<Profil?>()
        .firstWhere((p) => p?.id == s.profilId, orElse: () => null);
    final ouvert = _ouverts.contains(s.id);
    final neuve = !s.vuParAdmin;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Bloc(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        bordure: neuve ? Palette.orFonce.withValues(alpha: 0.5) : null,
        auClic: () {
          setState(() => ouvert ? _ouverts.remove(s.id) : _ouverts.add(s.id));
          if (neuve) _marquerVue(etat, s);
        },
        enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Pastille(qui?.nomComplet ?? '?',
                photoUrl: qui?.photoUrl, couleur: Palette.orFonce),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(qui?.nomComplet ?? 'Personne inconnue',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      if (neuve) ...[
                        const SizedBox(width: 8),
                        const Etiquette('Nouveau', couleur: Palette.orFonce),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                        'A quitté ${etat.nomFerme(s.fermeId)} · '
                        '${jourMois(s.moment)} à ${heure(s.moment)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(s.distance == null ? '—' : '${nb(s.distance)} m',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Palette.orFonce)),
              Text('de la ferme',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            Icon(ouvert ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: Theme.of(context).hintColor),
          ]),
          if (ouvert) ...[
            const Divider(height: 24),
            _chemin(context, etat, s),
          ],
        ]),
      ),
    );
  }

  /// Le chemin n'est chargé qu'à l'ouverture : inutile de tirer des
  /// centaines de points tant que personne ne les regarde.
  Widget _chemin(BuildContext context, Etat etat, SortieZone s) {
    if (s.pointageId == null) {
      return const Vide('Le pointage lié a été supprimé',
          icone: Icons.link_off_rounded);
    }
    return FutureBuilder<List<Trajet>>(
      future: Api.trajets(s.pointageId!),
      builder: (c, instantane) {
        if (instantane.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5))),
          );
        }
        if (instantane.hasError) {
          return Vide('Impossible de lire le chemin : ${instantane.error}',
              icone: Icons.wifi_off_rounded);
        }

        final points = instantane.data ?? [];
        // Seuls les points postérieurs à la sortie racontent le départ.
        final apres = s.moment == null
            ? points
            : points
                .where((t) =>
                    t.moment != null && !t.moment!.isBefore(s.moment!))
                .toList();
        if (apres.isEmpty) {
          return const Vide(
              'Aucun point enregistré après la sortie — le téléphone '
              'était éteint ou hors réseau',
              icone: Icons.location_off_outlined);
        }

        final parcourus = _distanceParcourue(apres);
        final dernier = apres.last;
        final duree = apres.first.moment == null || dernier.moment == null
            ? null
            : dernier.moment!.difference(apres.first.moment!).inMinutes;

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GrilleChiffres([
                CarteChiffre(
                    libelle: 'Distance parcourue',
                    valeur: parcourus < 1000
                        ? '${parcourus.round()} m'
                        : '${(parcourus / 1000).toStringAsFixed(1)} km',
                    complement: '${apres.length} point(s)',
                    couleur: Palette.bleu,
                    icone: Icons.route_rounded),
                CarteChiffre(
                    libelle: 'Suivi pendant',
                    valeur: duree == null ? '—' : '$duree min',
                    complement: 'jusqu’à ${heure(dernier.moment)}',
                    couleur: Palette.gris,
                    icone: Icons.schedule_rounded),
              ], largeurMin: 140),
              const TitreSection('Le chemin'),
              for (var i = 0; i < apres.length; i++)
                _point(context, apres[i], i, apres.length),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _ouvrirCarte(context, dernier),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Voir le dernier point sur une carte'),
                ),
              ),
            ]);
      },
    );
  }

  Widget _point(BuildContext context, Trajet t, int i, int total) {
    final premier = i == 0;
    final dernier = i == total - 1;
    final couleur =
        premier ? Palette.orFonce : (dernier ? Palette.vert : Palette.bleu);

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
          ),
          if (!dernier)
            Expanded(
              child: Container(
                  width: 2,
                  color: Theme.of(context).dividerColor,
                  margin: const EdgeInsets.symmetric(vertical: 2)),
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      premier
                          ? 'Départ de la ferme — ${heure(t.moment)}'
                          : (dernier
                              ? 'Dernier point connu — ${heure(t.moment)}'
                              : heure(t.moment)),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              premier || dernier ? FontWeight.w700 : FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                      t.distance == null
                          ? '${t.latitude.toStringAsFixed(5)}, '
                              '${t.longitude.toStringAsFixed(5)}'
                          : 'À ${nb(t.distance)} m de la ferme',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
          ),
        ),
      ]),
    );
  }

  /// La somme des sauts entre points successifs — une approximation
  /// honnête du chemin réel, qui suffit à voir si la personne est allée
  /// loin ou a tourné dans le quartier.
  double _distanceParcourue(List<Trajet> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += Localisation.distance(points[i - 1].latitude,
          points[i - 1].longitude, points[i].latitude, points[i].longitude);
    }
    return total;
  }

  Future<void> _ouvrirCarte(BuildContext context, Trajet t) async {
    final lien = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${t.latitude},${t.longitude}');
    try {
      await launchUrl(lien, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        message(context, 'Aucune application de carte sur ce téléphone.',
            erreur: true);
      }
    }
  }

  Future<void> _marquerVue(Etat etat, SortieZone s) async {
    try {
      await Api.marquerSortieVue(s.id);
      await etat.rafraichir();
    } catch (_) {
      // Sans réseau, la sortie restera marquée « nouveau ». Ce n'est
      // pas grave : rien n'est perdu, elle se relira plus tard.
    }
  }
}
