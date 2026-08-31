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
  bool _enregistrement = false;
  String? _dateChargee;

  @override
  void dispose() {
    for (final c in _champs.values) {
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
    final totalPoules = bats.fold<int>(0, (s, b) => s + b.nbPoules);
    final totalValeur = bats.fold(
        0, (s, b) => s + _nombre(b.id) * _prix(etat, b));
    final taux =
        totalPoules > 0 ? (totalOeufs / totalPoules * 100).round() : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          _dateChargee = null;
          await etat.rafraichir();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            _selecteurDate(context),
            const SizedBox(height: 14),
            if (bats.isEmpty)
              Bloc(
                  enfant: Vide(
                      'Aucun bâtiment sur votre ferme.\n'
                      '${etat.estGerant ? 'Ajoutez-en un depuis la fiche de la ferme.' : 'Demandez à votre gérant d’en créer un.'}',
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

  Widget _carteBatiment(BuildContext context, Etat etat, Batiment b) {
    final saisie = _saisieDe(etat, b.id);
    final nombre = _nombre(b.id);
    final prix = _prix(etat, b);
    final oeufs = nombre * oeufsParAlveole;
    final taux =
        b.nbPoules > 0 && nombre > 0 ? (oeufs / b.nbPoules * 100).round() : 0;
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
                      Text(
                          '${b.type} · ${nb(b.nbPoules)} poules · ${gnf(prix)}/alvéole',
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
                _tuile(context, 'Taux de ponte', taux > 0 ? '$taux %' : '—',
                    taux >= 85
                        ? Palette.vert
                        : (taux >= 70 ? Palette.orFonce : Palette.rouge)),
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
                Text('Taux de ponte : $taux %',
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
                '${parJour[j]!.length} bâtiment(s)'),
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
    message(
        context,
        erreur ??
            '${aEnregistrer.length} bâtiment(s) enregistré(s)'
                '${etat.estAdmin ? '' : ' — en attente de validation'}',
        erreur: erreur != null);
  }
}
