import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/comparaison.dart';
import '../core/elevage.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import '../widgets/photos.dart';
import 'formulaires.dart';

/// La santé du cheptel : combien de poules vivantes, combien de morts,
/// et où en est le calendrier vaccinal — tout calculé depuis le jour
/// d'arrivage du lot.
class EcranSante extends StatefulWidget {
  const EcranSante({super.key});

  @override
  State<EcranSante> createState() => _EcranSanteState();
}

class _EcranSanteState extends State<EcranSante> {
  String? _batimentOuvert;

  /// Le pourcentage de ponte de chaque bâtiment, tel que la BASE l'a
  /// calculé — le téléphone ne connaît qu'une partie des mortalités et
  /// des productions. Tout arrive en un seul appel : un appel par
  /// bâtiment, c'était autant d'occasions d'échouer. Voir sql/17.
  Map<String, PonteComparee>? _ponte;
  Panne? _panne;
  String? _cle;

  /// Le numéro de la demande en cours. Une réponse d'un numéro périmé
  /// est jetée. Une garde « une seule demande à la fois » avalait le
  /// premier tirer-vers-le-bas après un échec : il fallait tirer deux
  /// fois, et sur un réseau guinéen c'était le cas normal.
  int _demande = 0;

  void _assurerPonte(String? ferme, int tour) {
    // Le tour de lecture est dans la clé : après une déclaration de
    // mortalité, la même carte affichait « Vivantes 1 950 » rafraîchi
    // et « Ponte 92 % » calculé sur 2 000.
    final cle = '${ferme ?? 'tout'}|$tour';
    if (_cle == cle) return;
    _cle = cle;
    _chargerPonte(++_demande, ferme);
  }

  Future<void> _chargerPonte(int demande, String? ferme) async {
    try {
      final p = await Api.ponteCompareeParBatiment(fermeId: ferme)
          .timeout(const Duration(seconds: 25));
      if (!mounted || demande != _demande) return;
      setState(() {
        _ponte = p;
        _panne = null;
      });
    } catch (e) {
      // On garde les chiffres précédents : les effacer avant de tenter
      // la lecture privait l'utilisateur des seuls qu'il avait.
      if (!mounted || demande != _demande) return;
      setState(() => _panne = panneDe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final batiments = etat.estAdmin
        ? etat.batiments
        : etat.batimentsDe(etat.maFermeId);
    _assurerPonte(etat.estAdmin ? null : etat.maFermeId, etat.tour);

    final effectifDepart =
        batiments.fold<int>(0, (s, b) => s + b.nbPoules);
    final vivantes =
        batiments.fold<int>(0, (s, b) => s + etat.effectifVivant(b));
    // Une soustraction entre deux sources — l'effectif venu de la table
    // et les vivantes venues de la vue — affichait « Mortalité cumulée
    // −32,7 % » quand une des deux lectures échouait. Même source pour
    // les deux chiffres.
    final mortsTotal =
        batiments.fold<int>(0, (s, b) => s + etat.mortsCumules(b.id));
    final mortsAujourdhui = batiments.fold<int>(
        0, (s, b) => s + etat.mortsDuJour(b.id, aujourdhui()));

    return RefreshIndicator(
      // Le tour de lecture change à la fin du rafraîchissement, donc
      // les pourcentages se redemandent tout seuls.
      onRefresh: etat.rafraichir,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          GrilleChiffres([
            CarteChiffre(
                libelle: 'Poules vivantes',
                valeur: nb(vivantes),
                complement: 'sur ${nb(effectifDepart)} comptées',
                couleur: Palette.vert,
                icone: Icons.groups_rounded),
            CarteChiffre(
                libelle: 'Mortalité cumulée',
                valeur: effectifDepart > 0
                    ? pourcent(mortsTotal / effectifDepart * 100)
                    : '—',
                complement: '${nb(mortsTotal)} poules',
                couleur: Palette.rouge,
                icone: Icons.trending_down_rounded),
            CarteChiffre(
                libelle: 'Morts aujourd’hui',
                valeur: '$mortsAujourdhui',
                couleur: mortsAujourdhui == 0
                    ? Palette.vert
                    : (mortsAujourdhui > 5 ? Palette.rouge : Palette.orFonce),
                icone: Icons.today_rounded),
            CarteChiffre(
                libelle: 'Bâtiments suivis',
                valeur: '${batiments.where((b) => b.ageConnu).length}'
                    '/${batiments.length}',
                complement: 'avec jour d’arrivage',
                couleur: Palette.bleu,
                icone: Icons.warehouse_rounded),
          ]),
          const SizedBox(height: 18),
          // Une seule fois, en haut : la même phrase répétée sur chaque
          // carte, et un rouage par carte, encombraient tout l'écran.
          if (_panne != null && _ponte == null) ...[
            Bandeau(
              titre: 'Pourcentage de ponte indisponible',
              texte: direPanne(_panne!),
              couleur: Palette.orFonce,
              icone: _panne == Panne.reseau
                  ? Icons.wifi_off_rounded
                  : Icons.build_outlined,
            ),
            const SizedBox(height: 14),
          ] else if (_ponte == null) ...[
            Row(children: [
              const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Calcul des pourcentages de ponte…',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 14),
          ],
          if (batiments.isEmpty)
            const Bloc(
                enfant: Vide('Aucun bâtiment',
                    icone: Icons.warehouse_outlined))
          else
            for (final b in batiments) _carteBatiment(context, etat, b),
          const SizedBox(height: 18),
          _avertissement(context),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // UN BÂTIMENT
  // ══════════════════════════════════════════════════════════════════
  /// L'effectif a été compté par un fermier, pas par un responsable.
  /// Tout le pourcentage de ponte et le taux de mortalité reposent sur
  /// ce nombre : s'il est faux, tous les chiffres du bâtiment le sont.
  Widget _effectifAVerifier(BuildContext context, Etat etat, Batiment b) {
    final qui = etat.personnes
        .cast<Profil?>()
        .firstWhere((p) => p?.id == b.effectifPosePar, orElse: () => null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Bandeau(
        titre: 'Effectif à vérifier',
        texte: '${qui?.nomComplet ?? 'Quelqu’un'} a compté '
            '${nb(b.nbPoules)} poulets le ${jourMois(b.effectifPoseLe)}. '
            'Tout le pourcentage de ponte et la mortalité reposent sur ce '
            'nombre : si le compte est bon, confirmez ; sinon, corrigez-le.',
        couleur: Palette.orFonce,
        icone: Icons.pets_outlined,
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            onPressed: () => _corriger(context, etat, b),
            child: const Text('Corriger'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () async {
              final erreur =
                  await etat.agir(() => Api.confirmerEffectif(b.id));
              if (!context.mounted) return;
              message(context, erreur ?? 'Effectif confirmé',
                  erreur: erreur != null);
            },
            child: const Text('Confirmer'),
          ),
        ]),
      ),
    );
  }

  /// Corriger une faute de frappe sur le comptage.
  ///
  /// Sans ce chemin, un fermier qui tapait 20 000 au lieu de 2 000
  /// faussait tous les pourcentages de son bâtiment pour toujours : lui
  /// ne pouvait plus y revenir, et son gérant n'a pas accès à la fiche
  /// du bâtiment. La date du comptage n'est pas déplacée, donc les
  /// morts déjà déclarées restent déduites.
  Future<void> _corriger(
      BuildContext context, Etat etat, Batiment b) async {
    final champ = TextEditingController(text: '${b.nbPoules}');
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Corriger l’effectif de ${b.nom}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Le comptage du ${jourMois(b.effectifPoseLe)} dit '
              '${nb(b.nbPoules)} poulets. Les ${nb(etat.mortsCumules(b.id))} '
              'morts déclarées depuis restent déduites.',
              style: Theme.of(d).textTheme.bodySmall),
          const SizedBox(height: 14),
          TextField(
            controller: champ,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Nombre de poulets comptés', isDense: true),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(d, int.tryParse(champ.text.trim()) ?? 0),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    champ.dispose();
    if (n == null) return;
    if (n <= 0) {
      if (!context.mounted) return;
      message(context, 'Indiquez le bon nombre de poulets.', erreur: true);
      return;
    }
    final erreur = await etat.agir(() => Api.corrigerEffectif(b.id, n));
    if (!context.mounted) return;
    message(context, erreur ?? '${nb(n)} poulets enregistrés',
        erreur: erreur != null);
  }

  /// Le pourcentage de ponte, et ce qu'il valait avant.
  ///
  /// Les chiffres viennent de la BASE : le téléphone ne connaît qu'une
  /// partie des mortalités et des productions, et un pourcentage bâti
  /// là-dessus est faux. Voir sql/17_idiama_ponte.sql.
  Widget _comparaison(BuildContext context, Batiment b) {
    final tout = _ponte;
    // Ni rouage ni message ici : le haut de l'écran le dit déjà, une
    // seule fois pour tous les bâtiments.
    if (tout == null) return const SizedBox.shrink();

    if (b.nbPoules <= 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Row(children: [
          Icon(Icons.pets_outlined,
              size: 17, color: Theme.of(context).hintColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'Personne n’a encore compté les poules de ce bâtiment. '
                'Le fermier le fait depuis l’onglet Production, et le '
                'pourcentage de ponte apparaît aussitôt.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ]),
      );
    }

    // Absent de la réponse = aucune saisie validée sur la période.
    final p = tout[b.id] ?? PonteComparee.vide;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TitreSection('Pourcentage de ponte'),
        _ligneComparaison(context, 'Aujourd’hui', p.jour, p.jourAvant, 'hier'),
        _ligneComparaison(context, '7 derniers jours', p.septJours,
            p.septJoursAvant, 'les 7 jours d’avant'),
        _ligneComparaison(
            context, 'Ce mois', p.mois, p.moisAvant, 'le mois passé'),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Œufs ramassés rapportés aux poules vivantes de chaque jour — '
              'la mortalité déclarée est déduite. Seules les saisies '
              'validées comptent.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }

  Widget _ligneComparaison(BuildContext context, String quand, Ponte maintenant,
      Ponte avant, String contre) {
    final points = PonteComparee.ecart(maintenant, avant);
    final couleur = points == null
        ? Palette.gris
        // « comme avant » en orange contredisait le mot : sous un demi
        // point d'écart, il n'y a rien à signaler.
        : (points.abs() < 0.5
            ? Palette.gris
            : (points >= 0.5
                ? Palette.vert
                : (points > -2 ? Palette.orFonce : Palette.rouge)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 104,
          child: Text(quand, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
            maintenant.invraisemblable ? '?' : pourcent(maintenant.taux),
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              maintenant.invraisemblable
                  ? 'plus d’un œuf par poule : vérifiez les alvéoles saisies'
                  : (points == null
                      ? PonteComparee.direPourquoiRien(
                          maintenant, avant, contre)
                      : '${PonteComparee.direEcart(points)} contre $contre'),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: maintenant.invraisemblable
                      ? Palette.orFonce
                      : couleur)),
        ),
      ]),
    );
  }

  Widget _carteBatiment(BuildContext context, Etat etat, Batiment b) {
    final vivantes = etat.effectifVivant(b);
    final taux = etat.tauxMortalite(b);
    final ouvert = _batimentOuvert == b.id;
    final semaines = b.ageSemaines;
    final attendu = b.ageConnu ? ponteAttendue(semaines) : 0;

    // Le taux de ponte des 7 derniers jours, calculé par la BASE sur les
    // poules vivantes de chaque jour. Le téléphone le calculait lui-même
    // sur sa liste tronquée, sans filtrer les saisies non validées, et
    // divisait par le cheptel d'AUJOURD'HUI : un lot qui pondait pareil
    // paraissait en chute.
    final sept = _ponte?[b.id]?.septJours ?? Ponte.vide;
    final ponteReelle = sept.invraisemblable ? null : sept.taux;
    // Au moins quatre journées de ramassage avant de juger un lot sur
    // le standard de son âge : avec une seule saisie partielle, le
    // bandeau « Ponte inférieure au standard » tombait à tort.
    final ecart =
        (b.ageConnu && ponteReelle != null && attendu > 0 && sept.jours >= 4)
            ? ponteReelle - attendu
            : null;

    // Depuis combien de jours plus personne ne saisit ? Un bâtiment à
    // l'arrêt affichait « 2 000 vivantes, mortalité 0,0 % » en vert,
    // et rien ne disait que plus rien n'y était ramassé.
    final derniere = etat.productions
        .where((p) => p.batimentId == b.id && p.date != null)
        .fold<DateTime?>(
            null,
            (d, p) =>
                d == null || p.date!.isAfter(d) ? p.date : d);
    final silence = b.nbPoules > 0
        ? (derniere == null
            ? -1
            : aujourdhui().difference(jourDe(derniere)).inDays)
        : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          // ── En-tête ──
          InkWell(
            onTap: () =>
                setState(() => _batimentOuvert = ouvert ? null : b.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.nom,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                          b.ageConnu
                              ? '$semaines semaines · ${phaseDuLot(semaines)}'
                                  '${etat.estAdmin ? ' · ${etat.nomFerme(b.fermeId)}' : ''}'
                              : 'Jour d’arrivage non renseigné',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(ouvert
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
              ]),
            ),
          ),

          // ── L'effectif posé par un fermier, à vérifier ──
          // Le gérant le voit aussi : il est sur place, c'est lui qui
          // peut aller recompter, et le fermier ne peut plus y revenir.
          if ((etat.estAdmin || etat.estGerant) &&
              b.nbPoules > 0 &&
              b.effectifPosePar != null &&
              !b.effectifConfirme)
            _effectifAVerifier(context, etat, b),

          // ── La ponte, comparée à avant ──
          _comparaison(context, b),

          // ── Les trois chiffres ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(children: [
              _tuile(
                  context,
                  'Vivantes',
                  b.nbPoules > 0 ? nb(vivantes) : '—',
                  b.nbPoules > 0 ? 'sur ${nb(b.nbPoules)} comptées' : 'à compter',
                  b.nbPoules > 0 ? Palette.vert : Palette.gris),
              _tuile(
                  context,
                  'Mortalité',
                  b.nbPoules > 0 ? pourcent(taux) : '—',
                  b.ageConnu
                      ? 'normal < ${pourcent(mortaliteAcceptable(semaines))}'
                      : 'cumulée',
                  b.nbPoules == 0
                      ? Palette.gris
                      : (taux <= mortaliteAcceptable(b.ageConnu ? semaines : 0)
                          ? Palette.vert
                          : Palette.rouge)),
              _tuile(
                  context,
                  'Ponte 7 j',
                  ponteReelle == null ? '—' : pourcent(ponteReelle, decimales: 0),
                  b.ageConnu ? 'attendu $attendu %' : 'âge inconnu',
                  ecart == null
                      ? Palette.gris
                      : (ecart >= -5
                          ? Palette.vert
                          : (ecart >= -15 ? Palette.orFonce : Palette.rouge))),
            ]),
          ),

          // ── Le verdict ──
          if (ecart != null && ecart < -8)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: 'Ponte inférieure au standard de son âge',
                texte:
                    'À $semaines semaines, un lot en bonne santé pond autour de '
                    '$attendu %. Celui-ci est à ${pourcent(ponteReelle, decimales: 0)}, '
                    'soit ${ecart.abs().toStringAsFixed(0)} points de moins, '
                    'sur ${sept.jours} journée${sept.jours > 1 ? 's' : ''} de '
                    'ramassage. Regardez l’aliment, l’eau, la chaleur et les '
                    'vaccins.',
                couleur: ecart < -20 ? Palette.rouge : Palette.orFonce,
                icone: Icons.trending_down_rounded,
              ),
            ),
          // Les morts déclarées dépassent le nombre compté : le cheptel
          // tombe à zéro, toutes les journées sortent du pourcentage, et
          // le taux affiché se figeait sur sa dernière valeur saine sans
          // que rien ne l'explique.
          if (b.nbPoules > 0 && vivantes == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: 'Cheptel déclaré à zéro',
                texte:
                    'Les ${nb(etat.mortsCumules(b.id))} morts déclarées égalent '
                    'ou dépassent les ${nb(b.nbPoules)} poules comptées. Tant '
                    'que c’est le cas, aucun pourcentage de ponte ne peut être '
                    'calculé pour ce bâtiment. Vérifiez les déclarations de '
                    'mortalité, ou corrigez l’effectif compté.',
                couleur: Palette.rouge,
                icone: Icons.error_outline_rounded,
              ),
            ),
          // Un bâtiment à l'arrêt avait l'air en pleine forme : « 2 000
          // vivantes, mortalité 0,0 % », en vert, et rien ne disait que
          // plus personne n'y ramassait.
          if (silence >= 3 || silence == -1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: silence == -1
                    ? 'Aucun ramassage jamais saisi'
                    : 'Plus de ramassage depuis $silence jours',
                texte: silence == -1
                    ? 'Ce bâtiment a des poules mais aucune journée de '
                        'ramassage n’a été enregistrée. Sans saisie, aucun '
                        'pourcentage de ponte ne peut être calculé.'
                    : 'La dernière journée saisie est le '
                        '${jour(derniere)}. Tant que le ramassage n’est pas '
                        'enregistré, le pourcentage de ponte ne veut plus rien '
                        'dire.',
                couleur: silence >= 7 ? Palette.rouge : Palette.orFonce,
                icone: Icons.event_busy_outlined,
              ),
            ),
          if (!b.ageConnu)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Bandeau(
                titre: 'Renseignez le jour d’arrivage',
                texte:
                    'Sans lui, pas d’âge, donc pas de calendrier vaccinal ni de '
                    'comparaison au standard. ${etat.estAdmin ? 'Modifiez le bâtiment depuis l’onglet Fermes.' : 'Demandez-le à votre administrateur.'}',
                couleur: Palette.orFonce,
                icone: Icons.event_busy_outlined,
              ),
            ),

          // ── Boutons ──
          const Divider(height: 1),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.rouge,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const RoundedRectangleBorder()),
                onPressed: () => formulaireMortalite(context, b),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                label: const Text('Déclarer des morts'),
              ),
            ),
            // Confirmer veut dire « j'ai regardé », pas « le nombre est
            // scellé » : après une première correction, le gérant
            // n'avait plus aucun chemin pour en faire une seconde.
            if ((etat.estAdmin || etat.estGerant) && b.nbPoules > 0) ...[
              Container(
                  width: 1, height: 28, color: Theme.of(context).dividerColor),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: Palette.orFonce,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: const RoundedRectangleBorder()),
                  onPressed: () => _corriger(context, etat, b),
                  icon: const Icon(Icons.pets_outlined, size: 18),
                  label: const Text('Effectif'),
                ),
              ),
            ],
            Container(
                width: 1, height: 28, color: Theme.of(context).dividerColor),
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Palette.vertMoyen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: const RoundedRectangleBorder()),
                onPressed: () =>
                    setState(() => _batimentOuvert = ouvert ? null : b.id),
                icon: const Icon(Icons.vaccines_outlined, size: 18),
                label: const Text('Calendrier'),
              ),
            ),
          ]),

          // ── Le calendrier du lot ──
          if (ouvert) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: _calendrier(context, etat, b),
            ),
            _historiqueMortalite(context, etat, b),
          ],
        ]),
      ),
    );
  }

  Widget _tuile(BuildContext context, String libelle, String valeur,
          String sous, Color c) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
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
                      fontSize: 17, fontWeight: FontWeight.w800, color: c)),
            ),
            const SizedBox(height: 2),
            Text(sous,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );

  // ══════════════════════════════════════════════════════════════════
  // LE CALENDRIER VACCINAL, EN VRAIES DATES
  // ══════════════════════════════════════════════════════════════════
  Widget _calendrier(BuildContext context, Etat etat, Batiment b) {
    if (!b.ageConnu) {
      return const Vide(
          'Le calendrier apparaîtra dès que le jour d’arrivage sera renseigné.',
          icone: Icons.event_busy_outlined);
    }

    final age = b.ageJours;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.vaccines_rounded, size: 17, color: Palette.vert),
        const SizedBox(width: 8),
        Text('Calendrier du lot',
            style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        Text('arrivé le ${jour(b.dateMiseEnPlace)}',
            style: Theme.of(context).textTheme.labelSmall),
      ]),
      const SizedBox(height: 12),
      for (final e in programmeVaccinal) _etape(context, etat, b, e, age),
      const SizedBox(height: 6),
      _jalons(context, b),
    ]);
  }

  Widget _etape(BuildContext context, Etat etat, Batiment b, EtapeVaccin e,
      int age) {
    final fait = etat.vaccinFait(b.id, e.vaccin, e.jour);
    final datePrevue = b.dateAuJour(e.jour);
    final joursRestants = e.jour - age;

    final Color couleur;
    final IconData icone;
    final String statut;
    if (fait != null) {
      couleur = Palette.vert;
      icone = Icons.check_circle_rounded;
      statut = 'Fait le ${jour(fait.dateFaite)}';
    } else if (joursRestants < -7) {
      couleur = Palette.rouge;
      icone = Icons.error_rounded;
      statut = 'En retard de ${-joursRestants} jours';
    } else if (joursRestants <= 0) {
      couleur = Palette.orFonce;
      icone = Icons.notifications_active_rounded;
      statut = joursRestants == 0 ? 'À faire aujourd’hui' : 'À faire';
    } else if (joursRestants <= 7) {
      couleur = Palette.bleu;
      icone = Icons.schedule_rounded;
      statut = 'Dans $joursRestants jour(s)';
    } else {
      couleur = Palette.gris;
      icone = Icons.circle_outlined;
      statut = 'Plus tard';
    }

    final aVenirLointain = fait == null && joursRestants > 30;

    return Opacity(
      opacity: aVenirLointain ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: fait != null
            ? null
            : () => formulaireVaccination(context, b, e),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, size: 19, color: couleur),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.vaccin,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      'J${e.jour} · ${jour(datePrevue)} · ${e.voie}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (!aVenirLointain) ...[
                    const SizedBox(height: 2),
                    Text('Contre ${e.contre}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Etiquette(statut, couleur: couleur),
              if (fait == null && joursRestants <= 7)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Appuyer pour cocher',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Les grandes dates de la vie du lot, en plus des vaccins.
  Widget _jalons(BuildContext context, Batiment b) {
    final jalons = [
      (126, 'Entrée en ponte attendue', '18 semaines'),
      (182, 'Pic de ponte', '26 semaines'),
      (560, 'Fin de cycle / réforme', '80 semaines'),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Palette.or.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LES GRANDES DATES DE CE LOT',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        for (final (j, quoi, quand) in jalons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(
                  b.ageJours >= j
                      ? Icons.check_circle_outline_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 15,
                  color: b.ageJours >= j ? Palette.vert : Palette.gris),
              const SizedBox(width: 9),
              Expanded(
                child: Text(quoi,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Text('${jour(b.dateAuJour(j))}  ($quand)',
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // L'HISTORIQUE DES MORTS
  // ══════════════════════════════════════════════════════════════════
  Widget _historiqueMortalite(BuildContext context, Etat etat, Batiment b) {
    final lignes = etat.mortalites
        .where((m) => m.batimentId == b.id && m.nombre > 0)
        .toList()
      ..sort((a, c) => (c.date ?? DateTime(2000))
          .compareTo(a.date ?? DateTime(2000)));

    if (lignes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Palette.vert.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text('Aucune mortalité déclarée sur ce bâtiment.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DERNIÈRES DÉCLARATIONS',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        for (final m in lignes.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emojiCause(m.cause),
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.nombre} poule${m.nombre > 1 ? 's' : ''} · ${jour(m.date)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                            '${m.cause} · ${etat.nomPersonne(m.auteurId)}'
                            '${m.note.isEmpty ? '' : ' — ${m.note}'}',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (m.photos.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          GaleriePhotos(m.photos, taille: 56),
                        ],
                      ],
                    ),
                  ),
                  if (etat.estAdmin || etat.estGerant)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _supprimer(context, etat, m),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 18, color: Theme.of(context).hintColor),
                    ),
                ]),
          ),
      ]),
    );
  }

  Future<void> _supprimer(
      BuildContext context, Etat etat, Mortalite m) async {
    final ok = await confirmer(context,
        titre: 'Supprimer cette déclaration ?',
        texte: '${m.nombre} poule${m.nombre > 1 ? 's' : ''} le ${jour(m.date)}. '
            'L’effectif vivant sera recalculé.',
        ok: 'Supprimer',
        danger: true,
        icone: Icons.delete_outline_rounded);
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerMortalite(m.id));
    if (context.mounted) {
      message(context, e ?? 'Déclaration supprimée', erreur: e != null);
    }
  }

  Widget _avertissement(BuildContext context) => Bloc(
        padding: const EdgeInsets.all(15),
        enfant: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.medical_information_outlined,
              size: 19, color: Theme.of(context).hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le calendrier vaccinal et les taux de ponte affichés sont des '
              'repères courants pour des pondeuses en climat tropical. Ils '
              'servent à vous alerter, pas à remplacer votre vétérinaire : '
              'le programme réel dépend de la souche, du fournisseur de '
              'vaccins et des maladies présentes autour de vos fermes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
      );
}
