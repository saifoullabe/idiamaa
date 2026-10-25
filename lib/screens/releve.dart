import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/releve.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';

/// Le découpage du temps proposé au choix.
enum Periode { mois, trimestre, annee }

/// Le relevé de compte : tout ce qui s'est passé sur une période.
///
/// Il NE se sert PAS des listes de l'écran : elles sont plafonnées par
/// le serveur (200 pointages, 500 ventes…), et un relevé annuel bâti
/// sur elles afficherait « 8 jours pointés » pour une année entière,
/// sans le dire. Il relit donc la base, bornée par ses propres dates.
///
/// Chacun voit ce qui le regarde : le fermier ses propres saisies, le
/// gérant sa ferme, l'administrateur toutes ses fermes.
class EcranReleve extends StatefulWidget {
  const EcranReleve({super.key});

  @override
  State<EcranReleve> createState() => _EcranReleveState();
}

class _EcranReleveState extends State<EcranReleve> {
  Periode _periode = Periode.mois;
  late DateTime _ancre = aujourdhui();
  String? _ferme;
  String? _personne;

  _Donnees? _d;
  bool _charge = false;
  String? _echec;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculer());
  }

  // ── Les bornes de la période ───────────────────────────────────────
  DateTime get _debut => switch (_periode) {
        Periode.mois => DateTime(_ancre.year, _ancre.month, 1),
        Periode.trimestre =>
          DateTime(_ancre.year, ((_ancre.month - 1) ~/ 3) * 3 + 1, 1),
        Periode.annee => DateTime(_ancre.year, 1, 1),
      };

  /// Première seconde de la période SUIVANTE : on compare avec « avant »,
  /// ce qui évite d'oublier le dernier jour. DateTime gère le passage
  /// d'année tout seul : DateTime(2026, 13, 1) vaut janvier 2027.
  DateTime get _fin => switch (_periode) {
        Periode.mois => DateTime(_ancre.year, _ancre.month + 1, 1),
        Periode.trimestre =>
          DateTime(_ancre.year, ((_ancre.month - 1) ~/ 3) * 3 + 4, 1),
        Periode.annee => DateTime(_ancre.year + 1, 1, 1),
      };

  /// Sans accent typographique : l'exposant « ᵉ » n'existe dans aucune
  /// police embarquée et sortirait en case barrée au milieu du titre.
  String get _libellePeriode => switch (_periode) {
        Periode.mois => moisAnnee(_debut),
        Periode.trimestre =>
          'Trimestre ${((_debut.month - 1) ~/ 3) + 1} ${_debut.year}',
        Periode.annee => 'Annee ${_debut.year}',
      };

  void _decaler(int pas) {
    setState(() {
      _ancre = switch (_periode) {
        Periode.mois => DateTime(_ancre.year, _ancre.month + pas, 1),
        Periode.trimestre => DateTime(_ancre.year, _ancre.month + pas * 3, 1),
        Periode.annee => DateTime(_ancre.year + pas, _ancre.month, 1),
      };
    });
    _calculer();
  }

  // ── Qui entre dans le relevé ───────────────────────────────────────
  bool _concerne(Etat etat, String fermeId, String auteurId) {
    if (etat.estFermier) return auteurId == etat.moi!.id;
    if (_ferme != null && fermeId != _ferme) return false;
    if (_personne != null && auteurId != _personne) return false;
    return true;
  }

  bool _concernePersonne(Etat etat, String? fermeId, String profilId) {
    if (etat.estFermier) return profilId == etat.moi!.id;
    if (_ferme != null && fermeId != _ferme) return false;
    if (_personne != null && profilId != _personne) return false;
    return true;
  }

  // ── Le calcul, une seule fois par période ──────────────────────────
  Future<void> _calculer() async {
    if (!mounted) return;
    setState(() {
      _charge = true;
      _echec = null;
    });
    final etat = context.read<Etat>();
    // Portée serveur : l'admin peut tout lire, les autres sont de toute
    // façon bornés à leur ferme par les règles de la base.
    final portee = etat.estAdmin ? _ferme : etat.maFermeId;
    final d = _Donnees();

    try {
      final r = await Future.wait<dynamic>([
        Api.recettesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.depensesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.depotsEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.productionsEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.ventesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.mortalitesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.pointagesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.sortiesEntre(fermeId: portee, debut: _debut, fin: _fin),
        Api.recettesAvant(fermeId: portee, fin: _debut),
        Api.depensesAvant(fermeId: portee, fin: _debut),
        Api.depotsAvant(fermeId: portee, fin: _debut),
      ]).timeout(const Duration(seconds: 45));

      for (final x in r[0] as List<Recette>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        if (x.statut == Statut.valide) {
          d.recettes += x.montant;
          d.nbRecettes++;
          d.parProduit[x.produit] = (d.parProduit[x.produit] ?? 0) + x.montant;
        } else if (Statut.enAttente(x.statut)) {
          d.attenteRecettes += x.montant;
        }
      }
      for (final x in r[1] as List<Depense>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        if (x.statut == Statut.valide) {
          d.depenses += x.montant;
          d.nbDepenses++;
          d.parCategorie[x.categorie] =
              (d.parCategorie[x.categorie] ?? 0) + x.montant;
        } else if (Statut.enAttente(x.statut)) {
          d.attenteDepenses += x.montant;
        }
      }
      for (final x in r[2] as List<Depot>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        // Un dépôt va dans les DEUX sens : l'administration qui envoie
        // des fonds à la ferme, ou la ferme qui remonte sa caisse. Les
        // additionner gonflait le solde du double, du bon côté.
        final versLaFerme = x.roleAuteur == Role.admin;
        if (x.statut == Statut.valide) {
          if (versLaFerme) {
            d.depotsRecus += x.montant;
            d.nbDepots++;
          } else {
            d.depotsRemontes += x.montant;
            d.nbRemontes++;
          }
        } else if (Statut.enAttente(x.statut)) {
          d.attenteDepots += x.montant;
        }
      }
      for (final x in r[3] as List<Production>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        if (x.statut == Statut.valide) {
          d.oeufs += x.oeufs;
          d.alveoles += x.nbAlveoles;
          d.valeurProduite += x.valeur;
          if (x.date != null) d.joursProduction.add(iso(x.date!));
        } else if (Statut.enAttente(x.statut)) {
          d.oeufsEnAttente += x.oeufs;
        }
      }
      if (!etat.estFermier) {
        final recettes = r[0] as List<Recette>;
        for (final v in r[4] as List<Vente>) {
          if (_ferme != null && v.fermeId != _ferme) continue;
          if (_personne != null && v.auteurId != _personne) continue;
          final liee = recettes
              .cast<Recette?>()
              .firstWhere((x) => x?.id == v.recetteId, orElse: () => null);
          if (liee != null && liee.statut != Statut.valide) {
            d.ventesEnAttente += v.montant;
            continue;
          }
          d.alveolesVendues += v.nbAlveoles;
          d.montantVentes += v.montant;
          if (!v.paye) d.impayes += v.montant;
          d.nbVentes++;
        }
      }
      for (final x in r[5] as List<Mortalite>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        d.morts += x.nombre;
        d.parCause[x.cause] = (d.parCause[x.cause] ?? 0) + x.nombre;
      }
      for (final p in r[6] as List<Pointage>) {
        if (!_concernePersonne(etat, p.fermeId, p.profilId)) continue;
        // Le pointage encore ouvert compte jusqu'à maintenant : sinon
        // « jours pointés » comptait le jour et les heures non.
        d.secondesPresence += p.enCours ? p.dureeSecondes : (p.duree ?? 0);
        if (p.enCours) d.pointagesOuverts++;
        d.joursPointes.add(iso(p.debut.toLocal()));
        if (p.sortieAuto) d.sortiesAuto++;
      }
      for (final s in r[7] as List<SortieZone>) {
        if (!_concernePersonne(etat, s.fermeId, s.profilId)) continue;
        d.sortiesZone++;
      }

      // Le solde d'ouverture : ce qui était validé avant la période.
      for (final x in r[8] as List<Recette>) {
        if (_concerne(etat, x.fermeId, x.auteurId)) d.ouverture += x.montant;
      }
      for (final x in r[9] as List<Depense>) {
        if (_concerne(etat, x.fermeId, x.auteurId)) d.ouverture -= x.montant;
      }
      for (final x in r[10] as List<Depot>) {
        if (!_concerne(etat, x.fermeId, x.auteurId)) continue;
        d.ouverture +=
            x.roleAuteur == Role.admin ? x.montant : -x.montant;
      }

      if (!mounted) return;
      setState(() {
        _d = d;
        _charge = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _charge = false;
        _echec = e.toString().contains('Timeout')
            ? 'Le réseau n’a pas répondu. Réessayez quand il revient.'
            : 'Les chiffres n’ont pas pu être lus : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final d = _d;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await etat.rafraichir();
          await _calculer();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _choixPeriode(context),
            const SizedBox(height: 12),
            if (!etat.estFermier) _filtres(context, etat),
            if (!etat.estFermier) const SizedBox(height: 14),
            if (_echec != null)
              Bandeau(
                  titre: 'Relevé indisponible',
                  texte: _echec,
                  couleur: Palette.rouge,
                  icone: Icons.wifi_off_rounded)
            else if (_charge || d == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              GrilleChiffres([
                CarteChiffre(
                    libelle: 'Entrées',
                    valeur: gnfCourt(d.entrees),
                    complement: 'ventes et apports',
                    couleur: Palette.vert,
                    icone: Icons.south_west_rounded),
                CarteChiffre(
                    libelle: 'Sorties',
                    valeur: gnfCourt(d.sorties),
                    complement: '${d.nbDepenses} dépense(s)',
                    couleur: Palette.rouge,
                    icone: Icons.north_east_rounded),
                CarteChiffre(
                    libelle: 'Solde à la fin',
                    valeur: gnfCourt(d.cloture),
                    complement: 'ouverture ${gnfCourt(d.ouverture)}',
                    couleur: Palette.bleu,
                    icone: Icons.account_balance_wallet_outlined),
                CarteChiffre(
                    libelle: 'En attente',
                    valeur: gnfCourt(d.attenteTotal),
                    complement: d.attenteTotal == 0
                        ? 'rien à valider'
                        : 'entrées et sorties mêlées',
                    couleur:
                        d.attenteTotal == 0 ? Palette.gris : Palette.orFonce,
                    icone: Icons.hourglass_top_rounded),
              ], largeurMin: 150),
              const SizedBox(height: 18),
              for (final b in _blocs(etat, d)) _blocEcran(context, b),
            ],
          ],
        ),
      ),
      floatingActionButton: (d == null || _charge)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editer(context, etat, d),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Relevé PDF'),
            ),
    );
  }

  // ── La mise en forme, commune à l'écran et au PDF ───────────────────
  List<BlocReleve> _blocs(Etat etat, _Donnees d) {
    List<MapEntry<String, int>> tri(Map<String, int> m) =>
        m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Le libellé propre, jamais la clé de la base — et jamais `titre`,
    // qui commence par un emoji sans glyphe dans la police du PDF.
    String nomCategorie(String cle) => categoriesDepense
        .firstWhere((c) => c.cle == cle,
            orElse: () => const CategorieDepense(
                cle: '',
                libelle: 'Autre',
                emoji: '',
                couleur: Palette.gris,
                fond: Palette.beige,
                articles: []))
        .libelle;

    return [
      BlocReleve('Argent entré', [
        LigneReleve('Recettes validées', gnf(d.recettes),
            detail: '${d.nbRecettes} saisie(s)'),
        for (final e in tri(d.parProduit))
          LigneReleve('   ${e.key}', gnf(e.value)),
        if (d.depotsRecus > 0)
          LigneReleve('Apports de l’administration', gnf(d.depotsRecus),
              detail: '${d.nbDepots} dépôt(s) — ce n’est pas une recette'),
        LigneReleve('Total entré', gnf(d.entrees), gras: true),
      ]),
      BlocReleve('Argent sorti', [
        for (final e in tri(d.parCategorie))
          LigneReleve(nomCategorie(e.key), gnf(e.value)),
        if (d.depotsRemontes > 0)
          LigneReleve('Versements remontés à la direction',
              gnf(d.depotsRemontes),
              detail: '${d.nbRemontes} versement(s)'),
        LigneReleve('Total sorti', gnf(d.sorties), gras: true),
      ]),
      BlocReleve('Solde', [
        LigneReleve('Solde au début de la période', gnf(d.ouverture)),
        LigneReleve('Entrées', gnf(d.entrees)),
        LigneReleve('Sorties', gnf(d.sorties)),
        LigneReleve('Solde à la fin de la période', gnf(d.cloture), gras: true),
        LigneReleve('Résultat d’exploitation', gnf(d.recettes - d.depenses),
            detail: 'recettes moins dépenses, sans les apports'),
      ]),
      BlocReleve('En attente de validation', [
        LigneReleve('Recettes', gnf(d.attenteRecettes)),
        LigneReleve('Dépenses', gnf(d.attenteDepenses)),
        LigneReleve('Dépôts', gnf(d.attenteDepots)),
        LigneReleve('Œufs', nb(d.oeufsEnAttente)),
        LigneReleve('Rien de tout cela ne compte dans les totaux ci-dessus',
            '', detail: 'tant que l’échelon du dessus ne l’a pas validé'),
      ]),
      BlocReleve('Production', [
        LigneReleve('Œufs ramassés', nb(d.oeufs)),
        LigneReleve('Alvéoles', nb(d.alveoles), detail: '30 œufs par alvéole'),
        LigneReleve('Valeur de la production', gnf(d.valeurProduite)),
        LigneReleve('Jours avec saisie', '${d.joursProduction.length}'),
        if (d.joursProduction.isNotEmpty)
          LigneReleve('Moyenne par jour de saisie',
              '${nb(d.oeufs ~/ d.joursProduction.length)} œufs'),
      ]),
      if (!etat.estFermier)
        BlocReleve('Ventes aux revendeurs', [
          LigneReleve('Alvéoles vendues', nb(d.alveolesVendues),
              detail: '${d.nbVentes} achat(s)'),
          LigneReleve('Montant des ventes', gnf(d.montantVentes),
              detail: 'déjà compris dans les recettes — ne pas additionner'),
          if (d.ventesEnAttente > 0)
            LigneReleve('Ventes non encore validées', gnf(d.ventesEnAttente)),
          LigneReleve('Reste à encaisser sur ces ventes', gnf(d.impayes),
              gras: d.impayes > 0),
        ]),
      BlocReleve('Cheptel', [
        LigneReleve('Poules mortes', nb(d.morts)),
        for (final e in tri(d.parCause)) LigneReleve('   ${e.key}', nb(e.value)),
      ]),
      BlocReleve('Présence', [
        LigneReleve('Jours pointés', '${d.joursPointes.length}'),
        LigneReleve('Temps de présence', duree(d.secondesPresence),
            detail: d.pointagesOuverts > 0
                ? '${d.pointagesOuverts} pointage(s) encore ouvert(s), '
                    'comptés jusqu’à maintenant'
                : null),
        LigneReleve('Sorties de zone', '${d.sortiesZone}',
            detail: d.sortiesZone == 0
                ? 'personne n’a quitté la ferme en cours de pointage'
                : 'pointage fermé automatiquement',
            gras: d.sortiesZone > 0),
        LigneReleve('Pointages fermés par la base', '${d.sortiesAuto}',
            detail: 'sortie de zone ou téléphone silencieux'),
      ]),
    ];
  }

  Widget _blocEcran(BuildContext context, BlocReleve b) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Bloc(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          enfant:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TitreSection(b.titre),
            for (final l in b.lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.libelle,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: l.gras
                                          ? FontWeight.w800
                                          : FontWeight.w500)),
                              if (l.detail != null)
                                Text(l.detail!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ]),
                      ),
                      if (l.valeur.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(l.valeur,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: l.gras
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ]),
              ),
          ]),
        ),
      );

  // ── Les commandes ──────────────────────────────────────────────────
  Widget _choixPeriode(BuildContext context) => Bloc(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        enfant: Column(children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<Periode>(
              segments: const [
                ButtonSegment(value: Periode.mois, label: Text('Mois')),
                ButtonSegment(
                    value: Periode.trimestre, label: Text('Trimestre')),
                ButtonSegment(value: Periode.annee, label: Text('Année')),
              ],
              selected: {_periode},
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5))),
              onSelectionChanged: (s) {
                setState(() => _periode = s.first);
                _calculer();
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              onPressed: _charge ? null : () => _decaler(-1),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Période précédente',
            ),
            Flexible(
              child: Text(_libellePeriode,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              // On n'avance pas dans le futur : il n'y a rien à y lire.
              onPressed: (_charge || _fin.isAfter(aujourdhui()))
                  ? null
                  : () => _decaler(1),
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Période suivante',
            ),
          ]),
        ]),
      );

  Widget _filtres(BuildContext context, Etat etat) {
    final gens = etat.personnes
        .where((p) => _ferme == null || p.fermeId == _ferme)
        .toList();
    return Bloc(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      enfant: Row(children: [
        if (etat.estAdmin && etat.fermes.length > 1) ...[
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
              onChanged: (v) {
                setState(() {
                  _ferme = v;
                  _personne = null;
                });
                _calculer();
              },
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: _personne,
            isDense: true,
            decoration:
                const InputDecoration(labelText: 'Personne', isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tout le monde')),
              for (final p in gens)
                DropdownMenuItem(value: p.id, child: Text(p.nomComplet)),
            ],
            onChanged: (v) {
              setState(() => _personne = v);
              _calculer();
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _editer(BuildContext context, Etat etat, _Donnees d) async {
    final qui = _personne == null
        ? null
        : etat.personnes
            .cast<Profil?>()
            .firstWhere((p) => p?.id == _personne, orElse: () => null);

    final portee = etat.estFermier
        ? '${etat.moi!.nomComplet} — ses propres saisies'
        : [
            if (_ferme != null) etat.nomFerme(_ferme) else 'Toutes les fermes',
            if (qui != null) qui.nomComplet,
          ].join(' · ');

    try {
      await Releve.editer(
        // Pour un fermier, ce n'est pas un compte : c'est son journal.
        titre: etat.estFermier ? 'Mes saisies' : 'Relevé de compte',
        periode: _libellePeriode,
        portee: portee,
        editePar: etat.moi!.nomComplet,
        // Montants exacts : un chiffre arrondi sans le dire, sur un
        // relevé, est un chiffre faux.
        enTete: [
          LigneReleve('Entrées', gnf(d.entrees)),
          LigneReleve('Sorties', gnf(d.sorties)),
          LigneReleve('Solde à la fin', gnf(d.cloture)),
          LigneReleve('Œufs', nb(d.oeufs)),
        ],
        blocs: _blocs(etat, d),
      );
    } catch (e) {
      if (context.mounted) {
        message(context, 'Le relevé n’a pas pu être produit : $e', erreur: true);
      }
    }
  }
}

/// Les totaux d'une période, lus en base et bornés par ses dates.
class _Donnees {
  int recettes = 0;
  int depenses = 0;
  int depotsRecus = 0;
  int depotsRemontes = 0;
  int ouverture = 0;
  int nbRecettes = 0;
  int nbDepenses = 0;
  int nbDepots = 0;
  int nbRemontes = 0;

  int attenteRecettes = 0;
  int attenteDepenses = 0;
  int attenteDepots = 0;
  int oeufsEnAttente = 0;
  int ventesEnAttente = 0;

  int oeufs = 0;
  int alveoles = 0;
  int valeurProduite = 0;
  final Set<String> joursProduction = {};

  int alveolesVendues = 0;
  int montantVentes = 0;
  int impayes = 0;
  int nbVentes = 0;

  int morts = 0;
  final Map<String, int> parCause = {};
  final Map<String, int> parProduit = {};
  final Map<String, int> parCategorie = {};

  int secondesPresence = 0;
  int pointagesOuverts = 0;
  final Set<String> joursPointes = {};
  int sortiesZone = 0;
  int sortiesAuto = 0;

  int get entrees => recettes + depotsRecus;
  int get sorties => depenses + depotsRemontes;
  int get cloture => ouverture + entrees - sorties;
  int get attenteTotal => attenteRecettes + attenteDepenses + attenteDepots;
}
