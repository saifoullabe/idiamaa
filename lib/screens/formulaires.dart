import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/elevage.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/formulaire.dart';
import '../widgets/photos.dart';

/// Vérifie qu'on a le droit de saisir avant d'ouvrir un formulaire.
bool _autorise(BuildContext context, Etat etat) {
  if (etat.peutSaisir) return true;
  message(context, etat.raisonBlocage ?? 'Saisie impossible', erreur: true);
  return false;
}

// ══════════════════════════════════════════════════════════════════════
// RECETTE
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireRecette(BuildContext context) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;
  if (etat.maFermeId == null && !etat.estAdmin) {
    message(context, 'Aucune ferme ne vous est assignée.', erreur: true);
    return;
  }

  var produit = produitsRecette.first;
  var date = aujourdhui();
  String? fermeId = etat.maFermeId ?? (etat.fermes.isNotEmpty ? etat.fermes.first.id : null);
  final quantite = TextEditingController();
  final prixUnitaire = TextEditingController();
  final montant = TextEditingController();
  final description = TextEditingController();

  void recalculer() {
    final q = double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0;
    final p = double.tryParse(prixUnitaire.text.replaceAll(',', '.')) ?? 0;
    if (q > 0 && p > 0) montant.text = (q * p).round().toString();
  }

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Nouvelle recette',
    emoji: '💰',
    champs: (c, rafraichir) => [
      if (etat.estAdmin)
        ChampListe<String>(
          valeur: fermeId,
          libelle: 'Ferme',
          icone: Icons.holiday_village_outlined,
          options: [
            for (final f in etat.fermes)
              DropdownMenuItem(value: f.id, child: Text(f.nom)),
          ],
          auChangement: (v) {
            fermeId = v;
            rafraichir();
          },
        ),
      ChampListe<String>(
        valeur: produit,
        libelle: 'Produit vendu',
        icone: Icons.egg_outlined,
        options: [
          for (final p in produitsRecette)
            DropdownMenuItem(value: p, child: Text(p)),
        ],
        auChangement: (v) {
          produit = v!;
          rafraichir();
        },
      ),
      ChampDate(
        valeur: date,
        libelle: 'Date de la vente',
        auChangement: (d) {
          date = d;
          rafraichir();
        },
      ),
      Row(children: [
        Expanded(
          child: ChampNombre(quantite,
              libelle: 'Quantité',
              indice: 'ex : 420',
              auChangement: () {
                recalculer();
                rafraichir();
              }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChampNombre(prixUnitaire,
              libelle: 'Prix unitaire',
              indice: 'ex : 800',
              suffixe: 'GNF',
              auChangement: () {
                recalculer();
                rafraichir();
              }),
        ),
      ]),
      ChampNombre(montant,
          libelle: 'Montant total',
          argent: true,
          obligatoire: true,
          icone: Icons.payments_outlined),
      ChampTexte(description,
          libelle: 'Client / Note',
          indice: 'ex : Marché Madina',
          icone: Icons.person_outline_rounded),
      _noteValidation(c, etat),
    ],
    enregistrer: () async {
      final m = double.tryParse(montant.text.replaceAll(',', '.')) ?? 0;
      if (m <= 0) return 'Indiquez le montant total de la vente.';
      if (fermeId == null) return 'Choisissez une ferme.';
      return etat.agir(() => Api.creerRecette({
            'ferme_id': fermeId,
            'auteur_id': etat.moi!.id,
            'role_auteur': etat.role,
            'produit': produit,
            'quantite':
                double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0,
            'prix_unitaire':
                (double.tryParse(prixUnitaire.text.replaceAll(',', '.')) ?? 0)
                    .round(),
            'montant': m.round(),
            'description': description.text.trim(),
            'date': iso(date),
            'statut': Statut.aLaCreation(etat.role),
          }));
    },
  );
  if (ok && context.mounted) message(context, 'Recette enregistrée');
}

// ══════════════════════════════════════════════════════════════════════
// DÉPENSE
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireDepense(BuildContext context,
    {String? categorieDepart}) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  var cat = categorieDepart ?? categoriesDepense.first.cle;
  String? article;
  var articlePerso = false;
  var date = aujourdhui();
  String? fermeId =
      etat.maFermeId ?? (etat.fermes.isNotEmpty ? etat.fermes.first.id : null);
  final nouvelArticle = TextEditingController();
  final quantite = TextEditingController();
  final unite = TextEditingController();
  final prixUnitaire = TextEditingController();
  final montant = TextEditingController();
  final description = TextEditingController();

  List<String> articlesDe(String c) =>
      [...categorie(c).articles, ...(etat.articlesPerso[c] ?? const [])];

  void recalculer() {
    final q = double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0;
    final p = double.tryParse(prixUnitaire.text.replaceAll(',', '.')) ?? 0;
    if (q > 0 && p > 0) montant.text = (q * p).round().toString();
  }

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Nouvelle dépense',
    emoji: '📤',
    couleur: Palette.rouge,
    champs: (c, rafraichir) => [
      if (etat.estAdmin)
        ChampListe<String>(
          valeur: fermeId,
          libelle: 'Ferme',
          icone: Icons.holiday_village_outlined,
          options: [
            for (final f in etat.fermes)
              DropdownMenuItem(value: f.id, child: Text(f.nom)),
          ],
          auChangement: (v) {
            fermeId = v;
            rafraichir();
          },
        ),
      ChampListe<String>(
        valeur: cat,
        libelle: 'Catégorie',
        icone: Icons.category_outlined,
        options: [
          for (final x in categoriesDepense)
            DropdownMenuItem(value: x.cle, child: Text(x.titre)),
        ],
        auChangement: (v) {
          cat = v!;
          article = null;
          articlePerso = false;
          rafraichir();
        },
      ),
      ChampDate(
          valeur: date,
          libelle: 'Date',
          auChangement: (d) {
            date = d;
            rafraichir();
          }),
      ChampListe<String>(
        valeur: articlePerso ? '__autre__' : article,
        libelle: 'Désignation de l’article',
        icone: Icons.label_outline_rounded,
        options: [
          for (final a in articlesDe(cat))
            DropdownMenuItem(value: a, child: Text(a)),
          const DropdownMenuItem(
              value: '__autre__', child: Text('➕  Autre article…')),
        ],
        auChangement: (v) {
          if (v == '__autre__') {
            articlePerso = true;
            article = null;
          } else {
            articlePerso = false;
            article = v;
          }
          rafraichir();
        },
      ),
      if (articlePerso)
        ChampTexte(nouvelArticle,
            libelle: 'Nom du nouvel article',
            indice: 'Il sera proposé aux prochaines saisies',
            icone: Icons.add_circle_outline_rounded,
            obligatoire: true),
      Row(children: [
        Expanded(
          flex: 2,
          child: ChampNombre(quantite,
              libelle: 'Quantité',
              indice: 'ex : 50',
              auChangement: () {
                recalculer();
                rafraichir();
              }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChampTexte(unite, libelle: 'Unité', indice: 'kg'),
        ),
      ]),
      ChampNombre(prixUnitaire,
          libelle: 'Prix unitaire',
          indice: 'ex : 5000',
          suffixe: 'GNF',
          auChangement: () {
            recalculer();
            rafraichir();
          }),
      ChampNombre(montant,
          libelle: 'Montant total',
          argent: true,
          obligatoire: true,
          icone: Icons.money_off_csred_outlined),
      ChampTexte(description,
          libelle: 'Remarque',
          indice: 'Fournisseur, référence, détails…',
          lignes: 3),
      _noteValidation(c, etat),
    ],
    enregistrer: () async {
      final nom = articlePerso ? nouvelArticle.text.trim() : (article ?? '');
      if (nom.isEmpty) return 'Choisissez ou saisissez un article.';
      final m = double.tryParse(montant.text.replaceAll(',', '.')) ?? 0;
      if (m <= 0) return 'Indiquez le montant total de la dépense.';
      if (fermeId == null) return 'Choisissez une ferme.';
      return etat.agir(() async {
        if (articlePerso) {
          // On rattache le nouvel article à la ferme concernée, sinon
          // deux fermes ne pourraient pas avoir le même nom d'article.
          await Api.ajouterArticle(fermeId, cat, nom);
        }
        await Api.creerDepense({
          'ferme_id': fermeId,
          'auteur_id': etat.moi!.id,
          'role_auteur': etat.role,
          'categorie': cat,
          'article': nom,
          'quantite':
              double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0,
          'unite': unite.text.trim(),
          'prix_unitaire':
              (double.tryParse(prixUnitaire.text.replaceAll(',', '.')) ?? 0)
                  .round(),
          'montant': m.round(),
          'description': description.text.trim(),
          'date': iso(date),
          'statut': Statut.aLaCreation(etat.role),
        });
      });
    },
  );
  if (ok && context.mounted) message(context, 'Dépense enregistrée');
}

// ══════════════════════════════════════════════════════════════════════
// DÉPÔT D'ARGENT
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireDepot(BuildContext context) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  String? fermeId =
      etat.maFermeId ?? (etat.fermes.isNotEmpty ? etat.fermes.first.id : null);
  var date = aujourdhui();
  final montant = TextEditingController();
  final reference = TextEditingController();
  final motif = TextEditingController();
  final recus = <FichierChoisi>[];

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Nouveau dépôt',
    emoji: '🏦',
    couleur: Palette.bleu,
    champs: (c, rafraichir) => [
      if (etat.estAdmin)
        ChampListe<String>(
          valeur: fermeId,
          libelle: 'Ferme destinataire',
          icone: Icons.holiday_village_outlined,
          options: [
            for (final f in etat.fermes)
              DropdownMenuItem(value: f.id, child: Text(f.nom)),
          ],
          auChangement: (v) {
            fermeId = v;
            rafraichir();
          },
        ),
      ChampNombre(montant,
          libelle: 'Montant déposé',
          argent: true,
          obligatoire: true,
          icone: Icons.account_balance_wallet_outlined),
      ChampDate(
          valeur: date,
          libelle: 'Date du dépôt',
          auChangement: (d) {
            date = d;
            rafraichir();
          }),
      ChampTexte(reference,
          libelle: 'N° de reçu',
          indice: 'ex : REC-001',
          icone: Icons.confirmation_number_outlined),
      ChampTexte(motif,
          libelle: 'Motif', indice: 'ex : Fonds alimentation juin'),
      _zoneFichiers(c, recus, rafraichir),
      const SizedBox(height: 6),
      _noteValidation(c, etat),
    ],
    enregistrer: () async {
      final m = double.tryParse(montant.text.replaceAll(',', '.')) ?? 0;
      if (m <= 0) return 'Indiquez le montant du dépôt.';
      if (fermeId == null) return 'Choisissez une ferme.';
      return etat.agir(() async {
        final liens = <String>[];
        for (final f in recus) {
          liens.add(await Api.envoyerFichier(f, 'recus'));
        }
        await Api.creerDepot({
          'ferme_id': fermeId,
          'auteur_id': etat.moi!.id,
          'role_auteur': etat.role,
          'montant': m.round(),
          'date': iso(date),
          'reference': reference.text.trim(),
          'motif': motif.text.trim(),
          'fichiers': liens,
          'statut': Statut.aLaCreation(etat.role),
        });
      });
    },
  );
  if (ok && context.mounted) message(context, 'Dépôt enregistré');
}

// ══════════════════════════════════════════════════════════════════════
// FERME
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireFerme(BuildContext context, {Ferme? ferme}) async {
  final etat = context.read<Etat>();
  final nom = TextEditingController(text: ferme?.nom ?? '');
  final adresse = TextEditingController(text: ferme?.adresse ?? '');
  final ville = TextEditingController(text: ferme?.ville ?? '');
  final notes = TextEditingController(text: ferme?.notes ?? '');
  var statut = ferme?.statut ?? 'Actif';

  final ok = await ouvrirFormulaire(
    context,
    titre: ferme == null ? 'Nouvelle ferme' : 'Modifier la ferme',
    emoji: '🏚️',
    couleur: Palette.or,
    champs: (c, rafraichir) => [
      ChampTexte(nom,
          libelle: 'Nom de la ferme',
          indice: 'ex : Ferme Dubréka',
          icone: Icons.holiday_village_outlined,
          obligatoire: true),
      ChampTexte(ville,
          libelle: 'Ville / Préfecture',
          indice: 'ex : Dubréka',
          icone: Icons.location_city_rounded,
          obligatoire: true),
      ChampTexte(adresse,
          libelle: 'Adresse / Quartier',
          indice: 'ex : Route de Coyah, Km 12',
          icone: Icons.place_outlined),
      if (ferme != null)
        ChampListe<String>(
          valeur: statut,
          libelle: 'Statut',
          icone: Icons.flag_outlined,
          options: [
            for (final s in statutsFerme)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          auChangement: (v) {
            statut = v!;
            rafraichir();
          },
        ),
      ChampTexte(notes, libelle: 'Notes', lignes: 3),
      if (statut == 'Suspendue')
        const Bandeau(
          titre: 'Ferme suspendue',
          texte:
              'Le gérant et les fermiers de cette ferme ne pourront plus se connecter.',
          couleur: Palette.rouge,
          icone: Icons.block_rounded,
        ),
    ],
    enregistrer: () async {
      if (nom.text.trim().isEmpty) return 'Le nom de la ferme est obligatoire.';
      if (ville.text.trim().isEmpty) return 'La ville est obligatoire.';
      final champs = {
        'nom': nom.text.trim(),
        'ville': ville.text.trim(),
        'adresse': adresse.text.trim(),
        'notes': notes.text.trim(),
        'statut': statut,
      };
      return etat.agir(() => ferme == null
          ? Api.creerFerme(
              nom: champs['nom']!,
              ville: champs['ville']!,
              adresse: champs['adresse']!,
              notes: champs['notes']!)
          : Api.majFerme(ferme.id, champs));
    },
  );
  if (ok && context.mounted) message(context, 'Ferme enregistrée');
}

// ══════════════════════════════════════════════════════════════════════
// BÂTIMENT
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireBatiment(BuildContext context,
    {Batiment? batiment, String? fermeId}) async {
  final etat = context.read<Etat>();
  final cible = fermeId ?? batiment?.fermeId ?? etat.maFermeId;
  if (cible == null) {
    message(context, 'Choisissez d’abord une ferme.', erreur: true);
    return;
  }
  final prixDefaut = etat.ferme(cible)?.prixAlveole ?? prixAlveoleDefaut;

  final nom = TextEditingController(text: batiment?.nom ?? '');
  final poules =
      TextEditingController(text: batiment?.nbPoules.toString() ?? '');
  final prix = TextEditingController(
      text: (batiment?.prixAlveole ?? prixDefaut).toString());
  final surface =
      TextEditingController(text: batiment?.surface.toString() ?? '');
  var type = batiment?.type ?? typesBatiment.first;
  var etatBat = batiment?.etat ?? etatsBatiment.first;
  DateTime? miseEnPlace = batiment?.dateMiseEnPlace;

  final ok = await ouvrirFormulaire(
    context,
    titre: batiment == null ? 'Nouveau bâtiment' : 'Modifier le bâtiment',
    emoji: '🏗️',
    champs: (c, rafraichir) => [
      ChampTexte(nom,
          libelle: 'Nom du bâtiment',
          indice: 'ex : Bâtiment E',
          icone: Icons.warehouse_outlined,
          obligatoire: true),
      ChampListe<String>(
        valeur: type,
        libelle: 'Type',
        icone: Icons.category_outlined,
        options: [
          for (final t in typesBatiment)
            DropdownMenuItem(value: t, child: Text(t)),
        ],
        auChangement: (v) {
          type = v!;
          rafraichir();
        },
      ),
      Row(children: [
        Expanded(
            child: ChampNombre(poules,
                libelle: 'Effectif mis en place', indice: 'ex : 600')),
        const SizedBox(width: 12),
        Expanded(
            child:
                ChampNombre(surface, libelle: 'Surface', suffixe: 'm²')),
      ]),
      _champDateOptionnelle(c, 'Jour d’arrivage du lot', miseEnPlace, (d) {
        miseEnPlace = d;
        rafraichir();
      }),
      if (miseEnPlace == null)
        const Bandeau(
          titre: 'Renseignez le jour d’arrivage',
          texte:
              'C’est lui qui donne l’âge du lot. Sans âge, pas de calendrier '
              'vaccinal et pas de comparaison de la ponte au standard.',
          couleur: Palette.orFonce,
          icone: Icons.event_available_outlined,
        )
      else
        Bandeau(
          titre:
              'Lot de ${DateTime.now().difference(miseEnPlace!).inDays ~/ 7} semaines',
          texte:
              '${phaseDuLot(DateTime.now().difference(miseEnPlace!).inDays ~/ 7)}'
              ' · ponte attendue à cet âge : '
              '${ponteAttendue(DateTime.now().difference(miseEnPlace!).inDays ~/ 7)} %',
          couleur: Palette.vert,
          icone: Icons.cake_outlined,
        ),
      ChampNombre(prix,
          libelle: 'Prix d’une alvéole',
          argent: true,
          icone: Icons.sell_outlined),
      ChampListe<String>(
        valeur: etatBat,
        libelle: 'État du bâtiment',
        icone: Icons.health_and_safety_outlined,
        options: [
          for (final e in etatsBatiment)
            DropdownMenuItem(value: e, child: Text(e)),
        ],
        auChangement: (v) {
          etatBat = v!;
          rafraichir();
        },
      ),
    ],
    enregistrer: () async {
      if (nom.text.trim().isEmpty) return 'Le nom du bâtiment est obligatoire.';
      final champs = {
        'ferme_id': cible,
        'nom': nom.text.trim(),
        'type': type,
        'nb_poules': int.tryParse(poules.text) ?? 0,
        'prix_alveole': int.tryParse(prix.text) ?? prixDefaut,
        'surface': int.tryParse(surface.text) ?? 0,
        'etat': etatBat,
        'date_mise_en_place':
            miseEnPlace == null ? null : iso(miseEnPlace!),
      };
      return etat.agir(() => batiment == null
          ? Api.creerBatiment(champs)
          : Api.majBatiment(batiment.id, champs));
    },
  );
  if (ok && context.mounted) message(context, 'Bâtiment enregistré');
}

// ══════════════════════════════════════════════════════════════════════
// UTILISATEUR (gérant ou fermier)
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireUtilisateur(BuildContext context,
    {Profil? profil}) async {
  final etat = context.read<Etat>();
  final creation = profil == null;

  final login = TextEditingController(text: profil?.login ?? '');
  final motDePasse = TextEditingController();
  final nom = TextEditingController(text: profil?.nom ?? '');
  final prenom = TextEditingController(text: profil?.prenom ?? '');
  final tel = TextEditingController(text: profil?.tel ?? '');
  final tel2 = TextEditingController(text: profil?.tel2 ?? '');
  final lieuNaissance =
      TextEditingController(text: profil?.lieuNaissance ?? '');
  final pere = TextEditingController(text: profil?.pere ?? '');
  final mere = TextEditingController(text: profil?.mere ?? '');
  final quartier = TextEditingController(text: profil?.quartier ?? '');
  final commune = TextEditingController(text: profil?.commune ?? '');
  final salaire =
      TextEditingController(text: profil == null ? '' : '${profil.salaire}');
  final notes = TextEditingController(text: profil?.notes ?? '');

  var role = profil?.role ?? Role.fermier;
  String? fermeId = profil?.fermeId;
  DateTime? naissance = profil?.dateNaissance;
  DateTime? embauche = profil?.dateEmbauche;
  FichierChoisi? photo;
  FichierChoisi? piece;
  FichierChoisi? contrat;

  final ok = await ouvrirFormulaire(
    context,
    titre: creation ? 'Nouvel espace utilisateur' : 'Modifier la fiche',
    emoji: '👤',
    couleur: Palette.or,
    champs: (c, rafraichir) => [
      _selecteurPhoto(c, photo, profil?.photoUrl, (f) {
        photo = f;
        rafraichir();
      }),
      const SizedBox(height: 18),
      const SousTitreFormulaire('Rôle et accès'),
      ChampListe<String>(
        valeur: role,
        libelle: 'Rôle',
        icone: Icons.badge_outlined,
        options: const [
          DropdownMenuItem(value: Role.gerant, child: Text('🏚️  Gérant de ferme')),
          DropdownMenuItem(value: Role.fermier, child: Text('👨‍🌾  Fermier')),
          DropdownMenuItem(value: Role.admin, child: Text('👑  Administrateur')),
        ],
        auChangement: (v) {
          role = v!;
          if (role == Role.admin) fermeId = null;
          rafraichir();
        },
      ),
      if (role != Role.admin)
        ChampListe<String>(
          valeur: fermeId,
          libelle: 'Ferme assignée',
          icone: Icons.holiday_village_outlined,
          options: [
            const DropdownMenuItem(value: null, child: Text('— Aucune —')),
            for (final f in etat.fermes)
              DropdownMenuItem(value: f.id, child: Text(f.nom)),
          ],
          auChangement: (v) {
            fermeId = v;
            rafraichir();
          },
        ),
      ChampTexte(login,
          libelle: 'Identifiant de connexion',
          indice: 'ex : mamadou.bah',
          icone: Icons.alternate_email_rounded,
          obligatoire: creation),
      if (creation)
        ChampTexte(motDePasse,
            libelle: 'Mot de passe',
            indice: 'au moins 6 caractères',
            icone: Icons.lock_outline_rounded,
            obligatoire: true),
      if (!creation)
        const Bandeau(
          titre: 'Identifiant et mot de passe',
          texte:
              'Ils ne se modifient pas ici : la personne les change elle-même depuis « Mon compte ».',
          couleur: Palette.bleu,
        ),
      const SizedBox(height: 16),
      const SousTitreFormulaire('Identité'),
      Row(children: [
        Expanded(
            child: ChampTexte(nom,
                libelle: 'Nom de famille',
                indice: 'ex : BAH',
                obligatoire: true)),
        const SizedBox(width: 12),
        Expanded(
            child: ChampTexte(prenom,
                libelle: 'Prénom(s)',
                indice: 'ex : Mamadou',
                obligatoire: true)),
      ]),
      _champDateOptionnelle(c, 'Date de naissance', naissance, (d) {
        naissance = d;
        rafraichir();
      }),
      ChampTexte(lieuNaissance,
          libelle: 'Lieu de naissance', indice: 'ex : Conakry'),
      Row(children: [
        Expanded(
            child: ChampTexte(tel,
                libelle: 'Téléphone',
                indice: '+224 620 00 00 00',
                clavier: TextInputType.phone,
                icone: Icons.phone_outlined,
                obligatoire: true)),
      ]),
      ChampTexte(tel2,
          libelle: 'Téléphone 2',
          indice: 'facultatif',
          clavier: TextInputType.phone),
      const SizedBox(height: 6),
      const SousTitreFormulaire('Filiation et adresse'),
      Row(children: [
        Expanded(child: ChampTexte(pere, libelle: 'Nom du père')),
        const SizedBox(width: 12),
        Expanded(child: ChampTexte(mere, libelle: 'Nom de la mère')),
      ]),
      Row(children: [
        Expanded(
            child: ChampTexte(quartier,
                libelle: 'Quartier / Village', indice: 'ex : Matoto')),
        const SizedBox(width: 12),
        Expanded(
            child: ChampTexte(commune,
                libelle: 'Préfecture', indice: 'ex : Conakry')),
      ]),
      const SizedBox(height: 6),
      const SousTitreFormulaire('Poste et contrat'),
      _champDateOptionnelle(c, 'Date d’embauche', embauche, (d) {
        embauche = d;
        rafraichir();
      }),
      ChampNombre(salaire, libelle: 'Salaire mensuel', argent: true),
      ChampTexte(notes, libelle: 'Notes', lignes: 3),
      const SizedBox(height: 6),
      const SousTitreFormulaire('Documents'),
      _boutonFichier(
        c,
        titre: 'Pièce d’identité',
        sousTitre: piece != null
            ? 'Photo choisie'
            : (profil?.pieceUrl != null ? 'Déjà enregistrée' : 'CNI, passeport, permis'),
        icone: Icons.badge_outlined,
        auClic: () async {
          final f = await ImagePicker()
              .pickImage(source: ImageSource.gallery, imageQuality: 78);
          if (f != null) {
            piece = FichierChoisi(await f.readAsBytes(), f.name);
            rafraichir();
          }
        },
      ),
      const SizedBox(height: 10),
      _boutonFichier(
        c,
        titre: 'Contrat de travail (PDF)',
        sousTitre: contrat != null
            ? contrat!.nom
            : (profil?.contratUrl != null
                ? 'Déjà enregistré'
                : 'Aucun fichier joint'),
        icone: Icons.description_outlined,
        auClic: () async {
          final choisis = await FilePickerPlatform.instance.pickFiles(
              type: FileType.custom, allowedExtensions: ['pdf']);
          if (choisis.isNotEmpty) {
            final pdf = choisis.first;
            contrat = FichierChoisi(await pdf.readAsBytes(), pdf.name);
            rafraichir();
          }
        },
      ),
    ],
    enregistrer: () async {
      if (nom.text.trim().isEmpty || prenom.text.trim().isEmpty) {
        return 'Le nom et le prénom sont obligatoires.';
      }
      if (tel.text.trim().isEmpty) return 'Le téléphone est obligatoire.';
      if (creation) {
        if (login.text.trim().isEmpty) return 'L’identifiant est obligatoire.';
        if (motDePasse.text.length < 6) {
          return 'Le mot de passe doit faire au moins 6 caractères.';
        }
        if (role != Role.admin && fermeId == null) {
          return 'Choisissez la ferme de cette personne.';
        }
      }

      return etat.agir(() async {
        String? lienPhoto, lienPiece, lienContrat;
        if (photo != null) lienPhoto = await Api.envoyerFichier(photo!, 'photos');
        if (piece != null) lienPiece = await Api.envoyerFichier(piece!, 'pieces');
        if (contrat != null) {
          lienContrat = await Api.envoyerFichier(contrat!, 'contrats');
        }

        final champs = <String, dynamic>{
          'nom': nom.text.trim(),
          'prenom': prenom.text.trim(),
          'tel': tel.text.trim(),
          'tel2': tel2.text.trim(),
          'date_naissance': naissance == null ? null : iso(naissance!),
          'lieu_naissance': lieuNaissance.text.trim(),
          'pere': pere.text.trim(),
          'mere': mere.text.trim(),
          'quartier': quartier.text.trim(),
          'commune': commune.text.trim(),
          'date_embauche': embauche == null ? null : iso(embauche!),
          'salaire': int.tryParse(salaire.text) ?? 0,
          'notes': notes.text.trim(),
          if (lienPhoto != null) 'photo_url': lienPhoto,
          if (lienPiece != null) 'piece_url': lienPiece,
          if (lienContrat != null) 'contrat_url': lienContrat,
        };

        if (creation) {
          await Api.creerUtilisateur(
            login: login.text.trim(),
            motDePasse: motDePasse.text,
            nom: nom.text.trim(),
            prenom: prenom.text.trim(),
            role: role,
            fermeId: fermeId,
            autresChamps: champs,
          );
        } else {
          await Api.majProfil(profil.id, {
            ...champs,
            'role': role,
            'ferme_id': fermeId,
          });
        }
      });
    },
  );
  if (ok && context.mounted) {
    message(context, creation ? 'Espace créé' : 'Fiche mise à jour');
  }
}

// ══════════════════════════════════════════════════════════════════════
// SIGNALEMENT
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireSignalement(BuildContext context) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  final titre = TextEditingController();
  final description = TextEditingController();
  final images = <FichierChoisi>[];
  var priorite = 'normal';
  String? batimentId;

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Nouveau signalement',
    emoji: '⚠️',
    couleur: Palette.orFonce,
    libelleBouton: 'Envoyer au gérant',
    champs: (c, rafraichir) => [
      ChampTexte(titre,
          libelle: 'Titre',
          indice: 'ex : Mortalité anormale bâtiment D',
          icone: Icons.title_rounded,
          obligatoire: true),
      ChampListe<String>(
        valeur: priorite,
        libelle: 'Priorité',
        icone: Icons.priority_high_rounded,
        options: const [
          DropdownMenuItem(value: 'urgent', child: Text('🔴  Urgent')),
          DropdownMenuItem(value: 'normal', child: Text('🟡  Normal')),
          DropdownMenuItem(value: 'info', child: Text('🔵  Information')),
        ],
        auChangement: (v) {
          priorite = v!;
          rafraichir();
        },
      ),
      ChampListe<String>(
        valeur: batimentId,
        libelle: 'Bâtiment concerné',
        icone: Icons.warehouse_outlined,
        options: [
          const DropdownMenuItem(value: null, child: Text('— Aucun —')),
          for (final b in etat.batimentsDe(etat.maFermeId))
            DropdownMenuItem(value: b.id, child: Text(b.nom)),
        ],
        auChangement: (v) {
          batimentId = v;
          rafraichir();
        },
      ),
      ChampTexte(description,
          libelle: 'Description',
          indice: 'Décrivez le problème ou la chose à faire…',
          lignes: 5,
          obligatoire: true),
      ChoixPhotos(
        photos: images,
        auChangement: rafraichir,
        titre: 'Photos du problème',
      ),
      const SizedBox(height: 6),
      const Bandeau(
        titre: 'Une photo vaut mieux qu’un long texte',
        texte:
            'Le gérant et l’administrateur verront exactement ce que vous voyez.',
        couleur: Palette.bleu,
        icone: Icons.photo_camera_outlined,
      ),
    ],
    enregistrer: () async {
      if (titre.text.trim().isEmpty) return 'Donnez un titre au signalement.';
      if (description.text.trim().isEmpty) {
        return 'Décrivez ce qui se passe.';
      }
      return etat.agir(() async {
        final liens = await Api.envoyerFichiers(images, 'signalements');
        await Api.creerSignalement({
          'ferme_id': etat.maFermeId,
          'auteur_id': etat.moi!.id,
          'batiment_id': batimentId,
          'titre': titre.text.trim(),
          'priorite': priorite,
          'description': description.text.trim(),
          'date': iso(aujourdhui()),
          'statut': 'ouvert',
          'photos': liens,
        });
      });
    },
  );
  if (ok && context.mounted) message(context, 'Signalement envoyé au gérant');
}

// ══════════════════════════════════════════════════════════════════════
// RAPPORT D'ACTIVITÉ
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireRapport(BuildContext context) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  final titre =
      TextEditingController(text: 'Rapport du ${jour(aujourdhui())}');
  final activites = TextEditingController();
  final observations = TextEditingController();
  final images = <FichierChoisi>[];
  var date = aujourdhui();

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Rapport d’activité',
    emoji: '📋',
    couleur: Palette.bleu,
    libelleBouton: 'Envoyer',
    champs: (c, rafraichir) => [
      ChampTexte(titre,
          libelle: 'Titre',
          icone: Icons.title_rounded,
          obligatoire: true),
      ChampDate(
          valeur: date,
          libelle: 'Date',
          auChangement: (d) {
            date = d;
            rafraichir();
          }),
      ChampTexte(activites,
          libelle: 'Activités effectuées',
          indice:
              '- Distribution aliment 7h et 14h\n- Collecte œufs : 540 unités',
          lignes: 6),
      ChampTexte(observations,
          libelle: 'Observations',
          indice: 'Remarques, incidents…',
          lignes: 4),
      ChoixPhotos(
        photos: images,
        auChangement: rafraichir,
        titre: 'Photos de la journée',
      ),
    ],
    enregistrer: () async {
      if (titre.text.trim().isEmpty) return 'Donnez un titre au rapport.';
      return etat.agir(() async {
        final liens = await Api.envoyerFichiers(images, 'rapports');
        await Api.creerRapport({
          'ferme_id': etat.maFermeId,
          'auteur_id': etat.moi!.id,
          'titre': titre.text.trim(),
          'activites': activites.text.trim(),
          'observations': observations.text.trim(),
          'date': iso(date),
          'photos': liens,
        });
      });
    },
  );
  if (ok && context.mounted) message(context, 'Rapport envoyé');
}

// ══════════════════════════════════════════════════════════════════════
// MORTALITÉ
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireMortalite(BuildContext context, Batiment batiment,
    {DateTime? jourCible}) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  var date = jourCible ?? aujourdhui();
  final existante = etat.mortalites.cast<Mortalite?>().firstWhere(
        (m) =>
            m!.batimentId == batiment.id &&
            m.date != null &&
            iso(m.date!) == iso(date),
        orElse: () => null,
      );

  final nombre =
      TextEditingController(text: existante == null ? '' : '${existante.nombre}');
  final note = TextEditingController(text: existante?.note ?? '');
  final images = <FichierChoisi>[];
  var cause = existante?.cause ?? causesMortalite.first;

  final vivantes = etat.effectifVivant(batiment);

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Mortalité — ${batiment.nom}',
    emoji: '🪦',
    couleur: Palette.rouge,
    champs: (c, rafraichir) => [
      Bandeau(
        titre: '${nb(vivantes)} poules vivantes sur ${nb(batiment.nbPoules)}',
        texte: batiment.nbPoules > 0
            ? 'Mortalité cumulée : ${etat.tauxMortalite(batiment).toStringAsFixed(1)} % de l’effectif de départ.'
            : null,
        couleur: Palette.gris,
        icone: Icons.groups_outlined,
      ),
      const SizedBox(height: 16),
      ChampDate(
          valeur: date,
          libelle: 'Jour du constat',
          auChangement: (d) {
            date = d;
            rafraichir();
          }),
      ChampNombre(nombre,
          libelle: 'Nombre de poules mortes',
          indice: '0 si aucune',
          obligatoire: true,
          icone: Icons.remove_circle_outline_rounded,
          auChangement: rafraichir),
      ChampListe<String>(
        valeur: cause,
        libelle: 'Cause probable',
        icone: Icons.help_outline_rounded,
        options: [
          for (final x in causesMortalite)
            DropdownMenuItem(
                value: x, child: Text('${emojiCause(x)}  ${_libelleCause(x)}')),
        ],
        auChangement: (v) {
          cause = v!;
          rafraichir();
        },
      ),
      ChampTexte(note,
          libelle: 'Ce que vous avez observé',
          indice: 'ex : trouvées le matin près de l’abreuvoir',
          lignes: 3),
      ChoixPhotos(
        photos: images,
        auChangement: rafraichir,
        titre: 'Photos',
        maximum: 4,
      ),
      const SizedBox(height: 12),
      const Bandeau(
        titre: 'Déclarez même quand c’est zéro',
        texte:
            'Une journée sans mort est une information : c’est ce qui permet '
            'de repérer le jour où ça décroche.',
        couleur: Palette.bleu,
      ),
    ],
    enregistrer: () async {
      final n = int.tryParse(nombre.text);
      if (n == null || n < 0) return 'Indiquez le nombre de poules mortes.';
      if (n > vivantes + (existante?.nombre ?? 0)) {
        return 'Vous déclarez plus de morts qu’il n’y a de poules vivantes '
            '(${nb(vivantes)}). Vérifiez le chiffre.';
      }
      return etat.agir(() async {
        final liens = await Api.envoyerFichiers(images, 'mortalites');
        await Api.enregistrerMortalite({
          'ferme_id': batiment.fermeId,
          'batiment_id': batiment.id,
          'auteur_id': etat.moi!.id,
          'role_auteur': etat.role,
          'date': iso(date),
          'nombre': n,
          'cause': cause,
          'note': note.text.trim(),
          if (liens.isNotEmpty) 'photos': liens,
        });
      });
    },
  );
  if (ok && context.mounted) message(context, 'Mortalité enregistrée');
}

String _libelleCause(String c) => switch (c) {
      'inconnue' => 'Cause inconnue',
      'maladie' => 'Maladie',
      'chaleur' => 'Coup de chaleur',
      'écrasement' => 'Écrasement',
      'prédateur' => 'Prédateur',
      'accident' => 'Accident',
      'cannibalisme' => 'Picage / cannibalisme',
      'réforme' => 'Réforme (vendue)',
      _ => c,
    };

// ══════════════════════════════════════════════════════════════════════
// VACCINATION
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireVaccination(
    BuildContext context, Batiment batiment, EtapeVaccin etape) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  final prevue = batiment.dateAuJour(etape.jour);
  var date = (prevue != null && !prevue.isAfter(aujourdhui()))
      ? prevue
      : aujourdhui();
  final note = TextEditingController();
  final images = <FichierChoisi>[];

  final ok = await ouvrirFormulaire(
    context,
    titre: etape.vaccin,
    emoji: '💉',
    champs: (c, rafraichir) => [
      Bandeau(
        titre: 'Prévu au ${etape.jour}ᵉ jour du lot',
        texte: prevue == null
            ? null
            : 'soit le ${jour(prevue)} pour ${batiment.nom}.',
        couleur: Palette.vert,
        icone: Icons.event_rounded,
      ),
      const SizedBox(height: 14),
      Bloc(
        padding: const EdgeInsets.all(14),
        enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LigneInfo('Protège contre', etape.contre),
              LigneInfo('Voie d’administration', etape.voie),
            ]),
      ),
      const SizedBox(height: 16),
      ChampDate(
          valeur: date,
          libelle: 'Jour où le vaccin a été fait',
          auChangement: (d) {
            date = d;
            rafraichir();
          }),
      ChampTexte(note,
          libelle: 'Note',
          indice: 'Lot du vaccin, vétérinaire, difficulté rencontrée…',
          lignes: 3),
      ChoixPhotos(
        photos: images,
        auChangement: rafraichir,
        titre: 'Photos (flacon, ordonnance…)',
        maximum: 4,
      ),
    ],
    enregistrer: () => etat.agir(() async {
      final liens = await Api.envoyerFichiers(images, 'vaccins');
      await Api.enregistrerVaccination({
        'ferme_id': batiment.fermeId,
        'batiment_id': batiment.id,
        'auteur_id': etat.moi!.id,
        'role_auteur': etat.role,
        'vaccin': etape.vaccin,
        'age_jours': etape.jour,
        'date_faite': iso(date),
        'note': note.text.trim(),
        if (liens.isNotEmpty) 'photos': liens,
      });
    }),
  );
  if (ok && context.mounted) message(context, '${etape.vaccin} enregistré');
}

// ══════════════════════════════════════════════════════════════════════
// PHOTOS ENVOYÉES SEULES
// ══════════════════════════════════════════════════════════════════════
Future<void> formulairePhoto(BuildContext context) async {
  final etat = context.read<Etat>();
  if (!_autorise(context, etat)) return;

  final note = TextEditingController();
  final images = <FichierChoisi>[];
  String? batimentId;

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Envoyer des photos',
    emoji: '📷',
    couleur: Palette.bleu,
    libelleBouton: 'Envoyer',
    champs: (c, rafraichir) => [
      ChoixPhotos(
        photos: images,
        auChangement: rafraichir,
        titre: 'Photos à envoyer',
        maximum: 10,
      ),
      const SizedBox(height: 16),
      ChampTexte(note,
          libelle: 'Ce qu’on voit sur la photo',
          indice: 'ex : toiture du bâtiment D après la pluie',
          lignes: 3),
      ChampListe<String>(
        valeur: batimentId,
        libelle: 'Bâtiment concerné',
        icone: Icons.warehouse_outlined,
        options: [
          const DropdownMenuItem(value: null, child: Text('— Aucun —')),
          for (final b in etat.batimentsDe(etat.maFermeId))
            DropdownMenuItem(value: b.id, child: Text(b.nom)),
        ],
        auChangement: (v) {
          batimentId = v;
          rafraichir();
        },
      ),
    ],
    enregistrer: () async {
      if (images.isEmpty) return 'Choisissez au moins une photo.';
      return etat.agir(() async {
        final liens = await Api.envoyerFichiers(images, 'photos');
        for (final lien in liens) {
          await Api.creerPhoto({
            'ferme_id': etat.maFermeId,
            'auteur_id': etat.moi!.id,
            'role_auteur': etat.role,
            'url': lien,
            'note': note.text.trim(),
            'batiment_id': batimentId,
            'date': iso(aujourdhui()),
          });
        }
      });
    },
  );
  if (ok && context.mounted) message(context, 'Photos envoyées');
}

// ══════════════════════════════════════════════════════════════════════
// ARTICLE EN STOCK
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireStock(BuildContext context, {Stock? stock}) async {
  final etat = context.read<Etat>();
  final nom = TextEditingController(text: stock?.nom ?? '');
  final quantite = TextEditingController(
      text: stock == null ? '' : nb(stock.quantite).replaceAll(' ', ''));
  final seuil = TextEditingController(
      text: stock == null ? '' : nb(stock.seuilMin).replaceAll(' ', ''));
  final note = TextEditingController(text: stock?.note ?? '');
  var cat = stock?.categorie ?? categoriesDepense.first.cle;
  var unite = stock?.unite ?? unitesStock.first;

  final ok = await ouvrirFormulaire(
    context,
    titre: stock == null ? 'Nouvel article en stock' : 'Modifier l’article',
    emoji: '📦',
    champs: (c, rafraichir) => [
      ChampTexte(nom,
          libelle: 'Nom de l’article',
          indice: 'ex : Aliment pondeuse',
          icone: Icons.inventory_2_outlined,
          obligatoire: true),
      ChampListe<String>(
        valeur: cat,
        libelle: 'Catégorie',
        icone: Icons.category_outlined,
        options: [
          for (final x in categoriesDepense)
            DropdownMenuItem(value: x.cle, child: Text(x.titre)),
        ],
        auChangement: (v) {
          cat = v!;
          rafraichir();
        },
      ),
      Row(children: [
        Expanded(
            child: ChampNombre(quantite,
                libelle: stock == null ? 'Quantité de départ' : 'Quantité',
                indice: 'ex : 500')),
        const SizedBox(width: 12),
        Expanded(
          child: ChampListe<String>(
            valeur: unite,
            libelle: 'Unité',
            options: [
              for (final u in unitesStock)
                DropdownMenuItem(value: u, child: Text(u)),
            ],
            auChangement: (v) {
              unite = v!;
              rafraichir();
            },
          ),
        ),
      ]),
      ChampNombre(seuil,
          libelle: 'Seuil d’alerte',
          indice: 'en dessous, l’article passe en rouge',
          suffixe: unite,
          icone: Icons.notifications_active_outlined),
      ChampTexte(note, libelle: 'Note', indice: 'Fournisseur, détails…'),
    ],
    enregistrer: () async {
      if (nom.text.trim().isEmpty) return 'Le nom de l’article est obligatoire.';
      final champs = {
        'ferme_id': etat.maFermeId,
        'nom': nom.text.trim(),
        'categorie': cat,
        'unite': unite,
        'quantite': double.tryParse(quantite.text.replaceAll(',', '.')) ?? 0,
        'seuil_min': double.tryParse(seuil.text.replaceAll(',', '.')) ?? 0,
        'note': note.text.trim(),
      };
      return etat.agir(() => stock == null
          ? Api.creerStock(champs)
          : Api.majStock(stock.id, champs..remove('ferme_id')));
    },
  );
  if (ok && context.mounted) message(context, 'Article enregistré');
}

// ══════════════════════════════════════════════════════════════════════
// ATTRIBUTION — qui travaille sur cette ferme
// ══════════════════════════════════════════════════════════════════════
Future<void> formulaireAttribution(BuildContext context, Ferme ferme) async {
  final etat = context.read<Etat>();
  String? gerantId = ferme.gerantId;
  final choisis = etat
      .fermiers()
      .where((f) => f.fermeId == ferme.id)
      .map((f) => f.id)
      .toSet();

  final ok = await ouvrirFormulaire(
    context,
    titre: 'Attribution — ${ferme.nom}',
    emoji: '👥',
    couleur: Palette.bleu,
    champs: (c, rafraichir) => [
      ChampListe<String>(
        valeur: gerantId,
        libelle: 'Gérant de la ferme',
        icone: Icons.manage_accounts_outlined,
        options: [
          const DropdownMenuItem(value: null, child: Text('— Aucun gérant —')),
          for (final g in etat.gerants())
            DropdownMenuItem(
              value: g.id,
              child: Text(g.fermeId == null || g.fermeId == ferme.id
                  ? g.nomComplet
                  : '${g.nomComplet}  (actuellement ${etat.nomFerme(g.fermeId)})'),
            ),
        ],
        auChangement: (v) {
          gerantId = v;
          rafraichir();
        },
      ),
      const SousTitreFormulaire('Fermiers assignés'),
      if (etat.fermiers().isEmpty)
        const Vide('Aucun fermier créé pour le moment',
            icone: Icons.person_off_outlined),
      for (final f in etat.fermiers())
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          value: choisis.contains(f.id),
          title: Text(f.nomComplet,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(f.fermeId == null
              ? 'Sans ferme'
              : (f.fermeId == ferme.id
                  ? 'Déjà sur cette ferme'
                  : 'Actuellement : ${etat.nomFerme(f.fermeId)}')),
          secondary: Pastille(f.nomComplet, photoUrl: f.photoUrl, taille: 38),
          onChanged: (v) {
            v == true ? choisis.add(f.id) : choisis.remove(f.id);
            rafraichir();
          },
        ),
    ],
    enregistrer: () => etat.agir(() => Api.attribuer(
          fermeId: ferme.id,
          gerantId: gerantId,
          fermierIds: choisis.toList(),
        )),
  );
  if (ok && context.mounted) message(context, 'Attribution enregistrée');
}

// ── Petites briques partagées par les formulaires ────────────────────

Widget _noteValidation(BuildContext context, Etat etat) {
  if (etat.estAdmin) return const SizedBox.shrink();
  return Bandeau(
    titre: etat.estFermier
        ? 'La saisie part chez le gérant'
        : 'La saisie part chez l’administrateur',
    texte:
        'Elle ne comptera dans les totaux qu’une fois validée${etat.estFermier ? ' par votre gérant' : ''}.',
    couleur: Palette.or,
    icone: Icons.hourglass_top_rounded,
  );
}

Widget _champDateOptionnelle(BuildContext context, String libelle,
    DateTime? valeur, ValueChanged<DateTime> auChangement) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: valeur ?? DateTime(1995),
          firstDate: DateTime(1930),
          lastDate: DateTime.now(),
          locale: const Locale('fr', 'FR'),
        );
        if (d != null) auChangement(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: libelle,
          prefixIcon: const Icon(Icons.event_rounded, size: 20),
        ),
        child: Text(valeur == null ? 'Non renseignée' : jour(valeur),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valeur == null
                    ? Theme.of(context).hintColor
                    : null)),
      ),
    ),
  );
}

Widget _selecteurPhoto(BuildContext context, FichierChoisi? photo,
    String? urlExistante, ValueChanged<FichierChoisi> auChoix) {
  return Center(
    child: Column(children: [
      InkWell(
        borderRadius: BorderRadius.circular(60),
        onTap: () async {
          final f = await ImagePicker()
              .pickImage(source: ImageSource.gallery, imageQuality: 80);
          if (f != null) {
            auChoix(FichierChoisi(await f.readAsBytes(), f.name));
          }
        },
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                width: 2),
            image: photo != null
                ? DecorationImage(
                    image: MemoryImage(photo.octets), fit: BoxFit.cover)
                : (urlExistante != null && urlExistante.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(urlExistante), fit: BoxFit.cover)
                    : null),
          ),
          child: (photo == null &&
                  (urlExistante == null || urlExistante.isEmpty))
              ? Icon(Icons.add_a_photo_outlined,
                  size: 30, color: Theme.of(context).colorScheme.primary)
              : null,
        ),
      ),
      const SizedBox(height: 8),
      Text('Photo de profil',
          style: Theme.of(context).textTheme.labelMedium),
    ]),
  );
}

Widget _boutonFichier(
  BuildContext context, {
  required String titre,
  required String sousTitre,
  required IconData icone,
  required VoidCallback auClic,
}) {
  return Material(
    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: auClic,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icone, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(sousTitre,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.upload_file_rounded, size: 20),
        ]),
      ),
    ),
  );
}

Widget _zoneFichiers(BuildContext context, List<FichierChoisi> fichiers,
    VoidCallback rafraichir) {
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _boutonFichier(
      context,
      titre: 'Reçu justificatif',
      sousTitre: fichiers.isEmpty
          ? 'Photo du reçu ou fichier PDF'
          : '${fichiers.length} fichier(s) joint(s)',
      icone: Icons.receipt_long_outlined,
      auClic: () async {
        final choix = await showModalBottomSheet<String>(
          context: context,
          builder: (f) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(f, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () => Navigator.pop(f, 'galerie'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Choisir un PDF'),
                onTap: () => Navigator.pop(f, 'pdf'),
              ),
            ]),
          ),
        );
        if (choix == null) return;
        if (choix == 'pdf') {
          final choisis = await FilePickerPlatform.instance
              .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
          if (choisis.isNotEmpty) {
            final pdf = choisis.first;
            fichiers.add(FichierChoisi(await pdf.readAsBytes(), pdf.name));
          }
        } else {
          final f = await ImagePicker().pickImage(
            source:
                choix == 'photo' ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 72,
          );
          if (f != null) {
            fichiers.add(FichierChoisi(await f.readAsBytes(), f.name));
          }
        }
        rafraichir();
      },
    ),
    if (fichiers.isNotEmpty) ...[
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < fichiers.length; i++)
            Chip(
              backgroundColor: Palette.bleu.withValues(alpha: 0.12),
              label: Text(fichiers[i].nom, overflow: TextOverflow.ellipsis),
              onDeleted: () {
                fichiers.removeAt(i);
                rafraichir();
              },
            ),
        ],
      ),
    ],
  ]);
}
