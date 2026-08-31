import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/theme.dart';
import '../data/etat.dart';
import '../main.dart';
import '../widgets/communs.dart';
import 'depots.dart';
import 'depenses.dart';
import 'fermes.dart';
import 'mon_compte.dart';
import 'pointage.dart';
import 'presences.dart';
import 'productions.dart';
import 'rapport_global.dart';
import 'rapports.dart';
import 'recettes.dart';
import 'signalements.dart';
import 'stocks.dart';
import 'tableau_bord.dart';
import 'utilisateurs.dart';
import 'validation.dart';

/// Une page de l'application, telle qu'elle apparaît dans la barre du bas
/// ou dans le menu « Plus ».
class Onglet {
  final String titre;
  final IconData icone;
  final IconData iconePleine;
  final Widget page;
  final bool badge;

  const Onglet(this.titre, this.icone, this.iconePleine, this.page,
      {this.badge = false});
}

/// L'ossature de l'application : la barre du haut, les pages, la barre du bas.
class Coquille extends StatefulWidget {
  const Coquille({super.key});

  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> {
  int _index = 0;

  List<Onglet> _onglets(Etat etat) => switch (etat.role) {
        Role.admin => const [
            Onglet('Accueil', Icons.dashboard_outlined,
                Icons.dashboard_rounded, TableauBord()),
            Onglet('Validation', Icons.fact_check_outlined,
                Icons.fact_check_rounded, EcranValidation(),
                badge: true),
            Onglet('Fermes', Icons.holiday_village_outlined,
                Icons.holiday_village_rounded, EcranFermes()),
            Onglet('Équipe', Icons.groups_outlined, Icons.groups_rounded,
                EcranUtilisateurs()),
            Onglet('Présences', Icons.access_time_outlined,
                Icons.access_time_filled_rounded, EcranPresences()),
            Onglet('Recettes', Icons.payments_outlined,
                Icons.payments_rounded, EcranRecettes()),
            Onglet('Dépenses', Icons.receipt_long_outlined,
                Icons.receipt_long_rounded, EcranDepenses()),
            Onglet('Dépôts', Icons.account_balance_outlined,
                Icons.account_balance_rounded, EcranDepots()),
            Onglet('Rapport global', Icons.insert_chart_outlined,
                Icons.insert_chart_rounded, EcranRapportGlobal()),
          ],
        Role.gerant => const [
            Onglet('Accueil', Icons.dashboard_outlined,
                Icons.dashboard_rounded, TableauBord()),
            Onglet('Validation', Icons.fact_check_outlined,
                Icons.fact_check_rounded, EcranValidation(),
                badge: true),
            Onglet('Production', Icons.egg_outlined, Icons.egg_rounded,
                EcranProductions()),
            Onglet('Dépenses', Icons.receipt_long_outlined,
                Icons.receipt_long_rounded, EcranDepenses()),
            Onglet('Recettes', Icons.payments_outlined,
                Icons.payments_rounded, EcranRecettes()),
            Onglet('Dépôts', Icons.account_balance_outlined,
                Icons.account_balance_rounded, EcranDepots()),
            Onglet('Stocks', Icons.inventory_2_outlined,
                Icons.inventory_2_rounded, EcranStocks()),
            Onglet('Signalements', Icons.warning_amber_rounded,
                Icons.warning_rounded, EcranSignalements()),
            Onglet('Rapports', Icons.description_outlined,
                Icons.description_rounded, EcranRapports()),
            Onglet('Présences', Icons.access_time_outlined,
                Icons.access_time_filled_rounded, EcranPresences()),
          ],
        _ => const [
            Onglet('Accueil', Icons.dashboard_outlined,
                Icons.dashboard_rounded, TableauBord()),
            Onglet('Pointage', Icons.access_time_outlined,
                Icons.access_time_filled_rounded, EcranPointage()),
            Onglet('Production', Icons.egg_outlined, Icons.egg_rounded,
                EcranProductions()),
            Onglet('Dépenses', Icons.receipt_long_outlined,
                Icons.receipt_long_rounded, EcranDepenses()),
            Onglet('Recettes', Icons.payments_outlined,
                Icons.payments_rounded, EcranRecettes()),
            Onglet('Stocks', Icons.inventory_2_outlined,
                Icons.inventory_2_rounded, EcranStocks()),
            Onglet('Signalements', Icons.warning_amber_rounded,
                Icons.warning_rounded, EcranSignalements()),
            Onglet('Rapports', Icons.description_outlined,
                Icons.description_rounded, EcranRapports()),
            Onglet('Dépôts', Icons.account_balance_outlined,
                Icons.account_balance_rounded, EcranDepots()),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final onglets = _onglets(etat);
    if (_index >= onglets.length) _index = 0;
    final courant = onglets[_index];
    final couleurRole = Palette.duRole(etat.role);

    // Les quatre premiers onglets vont dans la barre du bas ;
    // le reste est rangé derrière le bouton « Plus ».
    const visibles = 4;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (sorti, _) {
        if (!sorti && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(courant.titre),
              Text(
                etat.estAdmin
                    ? 'Toutes les fermes'
                    : (etat.maFerme?.nom ?? 'Aucune ferme assignée'),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: couleurRole),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              onPressed: etat.chargement ? null : () => etat.rafraichir(),
              icon: etat.chargement
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2))
                  : const Icon(Icons.refresh_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10, left: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => _ouvrirMenu(context, etat, onglets),
                child: Pastille(etat.moi?.nomComplet ?? '?',
                    photoUrl: etat.moi?.photoUrl,
                    taille: 36,
                    couleur: couleurRole),
              ),
            ),
          ],
        ),
        body: Column(children: [
          if (etat.moi?.suspendu == true)
            _bandeauPleineLargeur(
              'Compte suspendu — aucune saisie possible',
              Palette.rouge,
              Icons.block_rounded,
            ),
          if (etat.estFermier && !etat.enLigne && etat.moi?.suspendu != true)
            InkWell(
              onTap: () => setState(() => _index = 1),
              child: _bandeauPleineLargeur(
                'Pointez votre arrivée pour pouvoir saisir',
                Palette.orFonce,
                Icons.timer_outlined,
              ),
            ),
          if (etat.erreur != null)
            _bandeauPleineLargeur(
                etat.erreur!, Palette.rouge, Icons.wifi_off_rounded),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (enfant, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.015), end: Offset.zero)
                      .animate(anim),
                  child: enfant,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey('${etat.role}-$_index'),
                child: courant.page,
              ),
            ),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index < visibles ? _index : visibles,
          onDestinationSelected: (i) {
            if (i == visibles) {
              _ouvrirMenu(context, etat, onglets);
            } else {
              setState(() => _index = i);
            }
          },
          destinations: [
            for (var i = 0; i < visibles && i < onglets.length; i++)
              NavigationDestination(
                icon: _icone(onglets[i], etat, plein: false),
                selectedIcon: _icone(onglets[i], etat, plein: true),
                label: onglets[i].titre,
              ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _resteUnBadge(onglets, visibles, etat),
                child: const Icon(Icons.more_horiz_rounded),
              ),
              label: 'Plus',
            ),
          ],
        ),
      ),
    );
  }

  bool _resteUnBadge(List<Onglet> onglets, int visibles, Etat etat) {
    if (etat.aValider == 0) return false;
    final i = onglets.indexWhere((o) => o.badge);
    return i >= visibles;
  }

  Widget _icone(Onglet o, Etat etat, {required bool plein}) {
    final ico = Icon(plein ? o.iconePleine : o.icone);
    if (!o.badge || etat.aValider == 0) return ico;
    return Badge(label: Text('${etat.aValider}'), child: ico);
  }

  Widget _bandeauPleineLargeur(String texte, Color couleur, IconData icone) =>
      Container(
        width: double.infinity,
        color: couleur.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texte,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: couleur)),
          ),
        ]),
      );

  // ── Le menu « Plus » ────────────────────────────────────────────────
  void _ouvrirMenu(BuildContext context, Etat etat, List<Onglet> onglets) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (feuille) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.94,
        builder: (_, controleur) => ListView(
          controller: controleur,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
          children: [
            _carteIdentite(context, etat),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 6),
              child: Text('TOUTES LES PAGES',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            for (var i = 0; i < onglets.length; i++)
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                selected: i == _index,
                selectedTileColor:
                    Palette.duRole(etat.role).withValues(alpha: 0.10),
                leading: Icon(onglets[i].icone,
                    color: i == _index ? Palette.duRole(etat.role) : null),
                title: Text(onglets[i].titre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: onglets[i].badge && etat.aValider > 0
                    ? Etiquette('${etat.aValider}',
                        couleur: Palette.orFonce)
                    : null,
                onTap: () {
                  Navigator.pop(feuille);
                  setState(() => _index = i);
                },
              ),
            const SizedBox(height: 6),
            const Divider(),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.key_rounded),
              title: const Text('Mon compte',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(feuille);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EcranMonCompte()));
              },
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.brightness_6_rounded),
              title: const Text('Apparence',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(switch (PreferencesTheme.of(context).mode) {
                ThemeMode.light => 'Clair',
                ThemeMode.dark => 'Sombre',
                ThemeMode.system => 'Comme le téléphone',
              }),
              onTap: () {
                final p = PreferencesTheme.of(context);
                p.changer(switch (p.mode) {
                  ThemeMode.system => ThemeMode.light,
                  ThemeMode.light => ThemeMode.dark,
                  ThemeMode.dark => ThemeMode.system,
                });
                Navigator.pop(feuille);
              },
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.logout_rounded, color: Palette.rouge),
              title: const Text('Déconnexion',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Palette.rouge)),
              onTap: () async {
                Navigator.pop(feuille);
                final ok = await confirmer(
                  context,
                  titre: 'Déconnexion',
                  texte:
                      'Voulez-vous vraiment quitter votre espace ${Role.libelle(etat.role).toLowerCase()} ?',
                  ok: 'Déconnexion',
                  icone: Icons.logout_rounded,
                  danger: true,
                );
                if (ok && context.mounted) {
                  setState(() => _index = 0);
                  await context.read<Etat>().deconnexion();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteIdentite(BuildContext context, Etat etat) {
    final couleurs = Palette.degradeRole(etat.role);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
            colors: couleurs,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Row(children: [
        Pastille(etat.moi?.nomComplet ?? '?',
            photoUrl: etat.moi?.photoUrl, taille: 52, couleur: Palette.or),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etat.moi?.nomComplet ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  '${Role.emoji(etat.role)}  ${Role.libelle(etat.role)}'
                  '${etat.maFerme != null ? ' · ${etat.maFerme!.nom}' : ''}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12)),
              const SizedBox(height: 2),
              Text('🔑 ${etat.moi?.login ?? ''}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }
}
