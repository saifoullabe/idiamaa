import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';

/// La saisie des alvéoles ramassées, bâtiment par bâtiment.
/// Une alvéole = 30 œufs ; la valeur suit le prix d'alvéole du bâtiment.
class EcranProductions extends StatefulWidget {
  const EcranProductions({super.key});

  @override
  State<EcranProductions> createState() => _EcranProductionsState();
}

class _EcranProductionsState extends State<EcranProductions> {
  DateTime _date = aujourdhui();
  final Map<String, TextEditingController> _champs = {};
  /// Les champs du premier comptage, un par batiment sans effectif.
  final Map<String, TextEditingController> _effectifs = {};
  bool _enregistrement = false;
  String? _dateChargee;

  @override
  void dispose() {
    for (final c in _champs.values) {
      c.dispose();
    }
    for (final c in _effectifs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Recharge les champs avec ce qui est déjà enregistré pour la date.
  void _prendreLesValeurs(Etat etat) {
    if (_dateChargee == iso(_date)) return;
    _dateChargee = iso(_date);
    for (final b in etat.batimentsDe(etat.maFermeId)) {
      final saisie = _saisieDe(etat, b.id);
      final controleur = _champs.putIfAbsent(b.id, () => TextEditingController());
      controleur.text =
          (saisie != null && saisie.nbAlveoles > 0) ? '${saisie.nbAlveoles}' : '';
    }
  }

  /// La saisie du jour pour ce bâtiment — il n'y en a qu'une,
  /// quel que soit celui qui l'a faite.
  Production? _saisieDe(Etat etat, String batimentId) {
    return etat.productions.cast<Production?>().firstWhere(
          (p) =>
              p!.batimentId == batimentId &&
              p.date != null &&
              iso(p.date!) == iso(_date),
          orElse: () => null,
        );
  }

  int _nombre(String batimentId) =>
      int.tryParse(_champs[batimentId]?.text ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final bats = etat.batimentsDe(etat.maFermeId);
    _prendreLesValeurs(etat);

    final totalAlveoles =
        bats.fold<int>(0, (s, b) => s + _nombre(b.id));
    final totalOeufs = totalAlveoles * oeufsParAlveole;
    // Les poules VIVANTES : sur l'effectif de départ, le pourcentage
    // baissait à mesure que le lot mourait, même quand les survivantes
    // pondaient très bien.
    // Seuls les bâtiments où quelque chose est tapé, et seulement
    // pour aujourd'hui : le bandeau divisait les œufs d'un bâtiment par
    // le cheptel de TOUTE la ferme et contredisait les cartes juste
    // au-dessus.
    final totalPoules = bats
        .where((b) => _nombre(b.id) > 0)
        .fold<int>(0, (s, b) => s + etat.effectifVivant(b));
    final totalValeur = bats.fold(
        0, (s, b) => s + _nombre(b.id) * _prix(etat, b));
    final taux = (iso(_date) == iso(aujourdhui()) && totalPoules > 0)
        ? (totalOeufs / totalPoules * 100).round()
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        // On ne remet PAS _dateChargee à null : tous les bandeaux de
        // l'application disent « tirez vers le bas pour réessayer », et
        // ce geste réécrivait les champs avec ce qui est enregistré —
        // c'est-à-dire du vide. Le fermier avait tapé 40, le réseau
        // avait coupé, il tirait vers le bas, et sa saisie disparaissait
        // sans un mot. Les nouvelles valeurs apparaîtront au prochain
        // changement de journée.
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            _selecteurDate(context),
            const SizedBox(height: 14),
            if (bats.isEmpty)
              Bloc(
                  enfant: Vide(
                      'Aucun bâtiment sur votre ferme.\n'
                      '${etat.estGerant ? 'Demandez à votre administrateur d’en créer un.' : 'Demandez à votre gérant d’en créer un.'}',
                      icone: Icons.warehouse_outlined))
            else ...[
              for (final b in bats) _carteBatiment(context, etat, b),
              const SizedBox(height: 6),
              _recapitulatif(context, totalAlveoles, totalOeufs, taux,
                  totalValeur),
            ],
            const SizedBox(height: 22),
            const TitreSection('Historique', emoji: '📅'),
            _historique(context, etat),
          ],
        ),
      ),
      floatingActionButton: bats.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _enregistrement ? null : () => _enregistrer(etat),
              icon: _enregistrement
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.3, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(_enregistrement ? 'Patientez…' : 'Enregistrer'),
            ),
    );
  }

  int _prix(Etat etat, Batiment b) => b.prixAlveole > 0
      ? b.prixAlveole
      : (etat.maFerme?.prixAlveole ?? prixAlveoleDefaut);

  Widget _selecteurDate(BuildContext context) {
    return Bloc(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      enfant: Row(children: [
        IconButton(
          onPressed: () => setState(() {
            _date = _date.subtract(const Duration(days: 1));
            _dateChargee = null;
          }),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                locale: const Locale('fr', 'FR'),
              );
              if (d != null) {
                setState(() {
                  _date = DateTime(d.year, d.month, d.day);
                  _dateChargee = null;
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Text('Journée de ramassage',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 3),
                Text(
                    iso(_date) == iso(aujourdhui())
                        ? 'Aujourd’hui — ${jour(_date)}'
                        : jourLong(_date),
                    style: Theme.of(context).textTheme.titleSmall),
              ]),
            ),
          ),
        ),
        IconButton(
          onPressed: iso(_date) == iso(aujourdhui())
              ? null
              : () => setState(() {
                    _date = _date.add(const Duration(days: 1));
                    _dateChargee = null;
                  }),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
    );
  }

  /// Tant que le bâtiment n'a pas d'effectif, le pourcentage de ponte
  /// ne peut pas se calculer. Le fermier est devant les cages : c'est
  /// lui qui compte. Il ne le pose qu'UNE fois — ensuite ce sont les
  /// morts déclarées qui font baisser le nombre de vivantes.
  Widget _demandeEffectif(BuildContext context, Etat etat, Batiment b) {
    final champ = _effectifs.putIfAbsent(b.id, TextEditingController.new);
    return Bloc(
      bordure: Palette.orFonce,
      enfant: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${b.nom} — combien de poulets ?',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            'Sans ce nombre, le pourcentage de ponte ne peut pas être '
            'calculé. Comptez une fois : ensuite, déclarez simplement '
            'les morts.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: champ,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Nombre de poulets',
                  isDense: true,
                  prefixIcon: Icon(Icons.pets_outlined, size: 20)),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () async {
              // La même règle que pour les alvéoles : on compte les
              // poules quand on est à la ferme. Deux boutons
              // « Enregistrer » sur le même écran et deux règles, cela
              // ne s'explique pas.
              if (!etat.peutSaisir) {
                message(context, etat.raisonBlocage ?? 'Saisie impossible',
                    erreur: true);
                return;
              }
              final n = int.tryParse(champ.text.trim());
              if (n == null || n <= 0) {
                message(context, 'Indiquez un nombre de poulets.',
                    erreur: true);
                return;
              }
              final erreur =
                  await etat.agir(() => Api.poserEffectif(b.id, n));
              if (!context.mounted) return;
              message(context, erreur ?? '${nb(n)} poulets enregistrés',
                  erreur: erreur != null);
            },
            child: const Text('Enregistrer'),
          ),
        ]),
      ]),
    );
  }

  Widget _carteBatiment(BuildContext context, Etat etat, Batiment b) {
    // Pas d'effectif : on demande le nombre AU-DESSUS de la saisie, on
    // ne la remplace pas. Le ramassage du jour doit pouvoir s'écrire
    // même si personne n'a encore compté les poulets — sinon un
    // bâtiment neuf perd ses premières journées d'œufs.
    if (b.nbPoules <= 0) {
      return Column(children: [
        _demandeEffectif(context, etat, b),
        const SizedBox(height: 12),
        _carteSaisie(context, etat, b),
      ]);
    }
    return _carteSaisie(context, etat, b);
  }

  Widget _carteSaisie(BuildContext context, Etat etat, Batiment b) {
    // Un bâtiment créé APRÈS le chargement de la journée n'avait pas de
    // contrôleur : le champ s'en fabriquait un à lui, le fermier voyait
    // bien ses 40 alvéoles, et « Enregistrer » répondait « saisissez au
    // moins une alvéole ». Le ramassage était perdu sans un mot.
    _champs.putIfAbsent(b.id, TextEditingController.new);

    final saisie = _saisieDe(etat, b.id);
    final nombre = _nombre(b.id);
    final prix = _prix(etat, b);
    final oeufs = nombre * oeufsParAlveole;
    // Sur les poules VIVANTES : c'est ce que la mise à jour des décès
    // sert à corriger. Sur l'effectif de départ, le taux baissait à
    // mesure que le lot mourait, même si les survivantes pondaient bien.
    final vivantes = etat.effectifVivant(b);
    // Et seulement pour AUJOURD'HUI : pour une journée passée, le
    // cheptel d'aujourd'hui n'est pas celui de ce jour-là, et le chiffre
    // s'écartait de dix points de celui que la base calcule.
    final aujourdHui = iso(_date) == iso(aujourdhui());
    final taux = (aujourdHui && vivantes > 0 && nombre > 0)
        ? (oeufs / vivantes * 100).round()
        : 0;
    final valeur = nombre * prix;
    final couleurEtat = switch (b.etat) {
      'Bon' => Palette.vert,
      'Correct' => Palette.orFonce,
      _ => Palette.rouge,
    };
    final bloque = saisie != null && saisie.statut == Statut.valide;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 4,
            width: double.infinity,
            color: couleurEtat,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.nom,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      // Les poules VIVANTES : la carte annonçait « 2 000
                      // poules » et le taux divisait par 1 700. Le
                      // fermier qui refaisait le calcul de tête
                      // trouvait autre chose que l'application.
                      Text(
                          b.nbPoules > 0
                              ? '${b.type} · ${nb(vivantes)} poules vivantes · '
                                  '${gnf(prix)}/alvéole'
                              : '${b.type} · poules à compter · '
                                  '${gnf(prix)}/alvéole',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (saisie != null) PuceStatut(saisie.statut, compact: true),
              ]),
              if (saisie != null && saisie.statut == Statut.rejete) ...[
                const SizedBox(height: 10),
                Bandeau(
                  titre: 'Saisie rejetée',
                  texte: saisie.motifRejet.isEmpty
                      ? 'Corrigez le nombre et enregistrez à nouveau.'
                      : saisie.motifRejet,
                  couleur: Palette.rouge,
                  icone: Icons.cancel_rounded,
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _champs[b.id],
                    enabled: !bloque,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Alvéoles',
                      hintText: '0',
                      helperText: bloque ? 'Déjà validée' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(children: [
                  _boutonPlus(context, b.id, 1, bloque),
                  const SizedBox(height: 6),
                  _boutonPlus(context, b.id, -1, bloque),
                ]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _tuile(context, 'Œufs', oeufs > 0 ? nb(oeufs) : '—',
                    Palette.vert),
                // « Ponte estimée » et pas « Taux de ponte » : ce
                // chiffre-là est calculé sur le téléphone, à partir de
                // ce qui est TAPÉ, et tant que le gérant n'a pas validé
                // il ne compte pas dans le vrai pourcentage. Sous le
                // même nom, le fermier lisait 60 % ici et un tiret dans
                // Santé, à la même minute.
                _tuile(
                    context,
                    'Ponte estimée',
                    taux > 0 ? '$taux %' : '—',
                    // Un tiret en rouge se lit comme une alerte : gris
                    // tant qu'il n'y a rien à juger. Mêmes seuils que
                    // partout ailleurs : 80 et 65.
                    taux == 0
                        ? Palette.gris
                        : (taux >= 80
                            ? Palette.vert
                            : (taux >= 65 ? Palette.orFonce : Palette.rouge))),
                _tuile(context, 'Valeur',
                    valeur > 0 ? gnfCourt(valeur) : '—', Palette.or),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _boutonPlus(BuildContext context, String id, int pas, bool bloque) {
    return SizedBox(
      width: 46,
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: bloque
            ? null
            : () => setState(() {
                  final v = (_nombre(id) + pas).clamp(0, 99999);
                  _champs[id]!.text = v == 0 ? '' : '$v';
                }),
        child: Icon(pas > 0 ? Icons.add_rounded : Icons.remove_rounded,
            size: 19),
      ),
    );
  }

  Widget _tuile(BuildContext context, String libelle, String valeur, Color c) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(children: [
            Text(libelle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(valeur,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c)),
            ),
          ]),
        ),
      );

  Widget _recapitulatif(BuildContext context, int alveoles, int oeufs,
      int taux, int valeur) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Palette.vertMoyen, Palette.vert],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL DU JOUR',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 5),
              Text('$alveoles alvéoles · ${nb(oeufs)} œufs',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              if (taux > 0)
                Text('Ponte estimée : $taux % — le pourcentage officiel '
                    'apparaît après validation',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11.5)),
            ],
          ),
        ),
        Text(gnfCourt(valeur),
            style: const TextStyle(
                color: Color(0xFFFDD835),
                fontSize: 20,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _historique(BuildContext context, Etat etat) {
    final parJour = <String, List<Production>>{};
    for (final p in etat.productions) {
      parJour.putIfAbsent(iso(p.date ?? aujourdhui()), () => []).add(p);
    }
    final jours = parJour.keys.toList()..sort((a, b) => b.compareTo(a));

    if (jours.isEmpty) {
      return const Bloc(
          enfant: Vide('Aucune production enregistrée',
              icone: Icons.calendar_month_outlined));
    }

    return Bloc(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      enfant: Column(children: [
        for (final j in jours.take(30))
          ListTile(
            dense: true,
            onTap: () => setState(() {
              _date = DateTime.parse(j);
              _dateChargee = null;
            }),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Palette.vert.withValues(alpha: 0.12),
              child: Text('${parJour[j]!.fold<int>(0, (s, p) => s + p.nbAlveoles)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Palette.vert)),
            ),
            title: Text(jour(DateTime.parse(j)),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${nb(parJour[j]!.fold<int>(0, (s, p) => s + p.oeufs))} œufs · '
                '${parJour[j]!.length} bâtiment'
                '${parJour[j]!.length > 1 ? 's' : ''}'),
            trailing: Text(
                gnfCourt(parJour[j]!.fold<int>(0, (s, p) => s + p.valeur)),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Palette.orFonce)),
          ),
      ]),
    );
  }

  Future<void> _enregistrer(Etat etat) async {
    if (!etat.peutSaisir) {
      message(context, etat.raisonBlocage ?? 'Saisie impossible', erreur: true);
      return;
    }
    final bats = etat.batimentsDe(etat.maFermeId);
    final aEnregistrer = bats.where((b) => _nombre(b.id) > 0).toList();
    if (aEnregistrer.isEmpty) {
      message(context, 'Saisissez au moins une alvéole.', erreur: true);
      return;
    }

    setState(() => _enregistrement = true);
    final erreur = await etat.agir(() async {
      for (final b in aEnregistrer) {
        final dejaValidee = _saisieDe(etat, b.id)?.statut == Statut.valide;
        if (dejaValidee) continue;
        await Api.enregistrerProduction(
          fermeId: etat.maFermeId!,
          batimentId: b.id,
          auteurId: etat.moi!.id,
          roleAuteur: etat.role,
          date: _date,
          nbAlveoles: _nombre(b.id),
          prixAlveole: _prix(etat, b),
        );
      }
    });
    if (!mounted) return;
    setState(() {
      _enregistrement = false;
      _dateChargee = null;
    });
    // Les champs ne sont rechargés QUE si tout est passé : sinon les
    // alvéoles des bâtiments non enregistrés étaient effacées, sous un
    // message qui demande de regarder avant de ressaisir.
    if (erreur == null) _dateChargee = null;
    message(
        context,
        erreur ??
            (aEnregistrer.length == 1
                    ? 'Ramassage enregistré'
                    : '${aEnregistrer.length} bâtiments enregistrés') +
                (etat.estAdmin ? '' : ' — en attente de validation'),
        erreur: erreur != null);
  }
}
