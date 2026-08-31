import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../models/modeles.dart';
import '../widgets/communs.dart';
import 'formulaires.dart';

/// Les espaces de connexion : administrateurs, gérants, fermiers.
class EcranUtilisateurs extends StatefulWidget {
  const EcranUtilisateurs({super.key});

  @override
  State<EcranUtilisateurs> createState() => _EcranUtilisateursState();
}

class _EcranUtilisateursState extends State<EcranUtilisateurs> {
  String _recherche = '';

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();

    List<Profil> filtrer(String role) => etat.personnes
        .where((p) =>
            p.role == role &&
            (_recherche.isEmpty ||
                p.nomComplet.toLowerCase().contains(_recherche) ||
                p.login.toLowerCase().contains(_recherche)))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: etat.rafraichir,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextField(
              onChanged: (v) => setState(() => _recherche = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Rechercher un nom ou un identifiant…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            _groupe(context, etat, '👑  Administrateurs', filtrer(Role.admin)),
            _groupe(context, etat, '🏚️  Gérants de ferme', filtrer(Role.gerant)),
            _groupe(context, etat, '👨‍🌾  Fermiers', filtrer(Role.fermier)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => formulaireUtilisateur(context),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Créer un espace'),
      ),
    );
  }

  Widget _groupe(
      BuildContext context, Etat etat, String titre, List<Profil> gens) {
    return Column(children: [
      TitreSection('$titre  (${gens.length})'),
      if (gens.isEmpty)
        const Bloc(
            enfant: Vide('Personne dans ce groupe',
                icone: Icons.person_off_outlined))
      else
        for (final p in gens)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Bloc(
              auClic: () => _fiche(context, etat, p),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enfant: Row(children: [
                Pastille(p.nomComplet,
                    photoUrl: p.photoUrl,
                    taille: 46,
                    couleur: Palette.duRole(p.role)),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(p.nomComplet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                        ),
                        if (p.suspendu) ...[
                          const SizedBox(width: 8),
                          const Etiquette('Suspendu',
                              couleur: Palette.rouge,
                              icone: Icons.block_rounded),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      Text(
                          '🔑 ${p.login}'
                          '${p.fermeId != null ? ' · ${etat.nomFerme(p.fermeId)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (p.tel.isNotEmpty)
                        Text('📞 ${p.tel}',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
    ]);
  }

  // ── Fiche complète ────────────────────────────────────────────────
  void _fiche(BuildContext context, Etat etat, Profil p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (feuille) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controleur) => ListView(
          controller: controleur,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: Palette.degradeRole(p.role),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(children: [
                Pastille(p.nomComplet,
                    photoUrl: p.photoUrl, taille: 64, couleur: Palette.or),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nomComplet,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                          '${Role.emoji(p.role)} ${Role.libelle(p.role)}'
                          '${p.fermeId != null ? ' · ${etat.nomFerme(p.fermeId)}' : ''}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12)),
                      const SizedBox(height: 3),
                      Text('🔑 ${p.login} · depuis le ${jour(p.creeLe)}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ]),
            ),
            if (p.suspendu) ...[
              const SizedBox(height: 14),
              const Bandeau(
                titre: 'Compte suspendu',
                texte:
                    'Cette personne peut se connecter mais ne peut plus rien saisir.',
                couleur: Palette.rouge,
                icone: Icons.block_rounded,
              ),
            ],
            const TitreSection('Identité'),
            Bloc(
              enfant: Column(children: [
                LigneInfo('Nom et prénom', p.nomComplet),
                LigneInfo('Date de naissance', jour(p.dateNaissance)),
                LigneInfo('Lieu de naissance', p.lieuNaissance),
                LigneInfo('Téléphone', p.tel),
                LigneInfo('Téléphone 2', p.tel2),
              ]),
            ),
            const TitreSection('Filiation et adresse'),
            Bloc(
              enfant: Column(children: [
                LigneInfo('Père', p.pere),
                LigneInfo('Mère', p.mere),
                LigneInfo('Quartier', p.quartier),
                LigneInfo('Préfecture', p.commune),
              ]),
            ),
            const TitreSection('Poste et contrat'),
            Bloc(
              enfant: Column(children: [
                LigneInfo('Date d’embauche', jour(p.dateEmbauche)),
                LigneInfo('Salaire mensuel',
                    p.salaire > 0 ? gnf(p.salaire) : '—'),
                LigneInfo('Notes', p.notes),
              ]),
            ),
            const TitreSection('Documents'),
            Bloc(
              enfant: Row(children: [
                Expanded(
                  child: _document(context, 'Pièce d’identité',
                      Icons.badge_outlined, p.pieceUrl),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _document(context, 'Contrat de travail',
                      Icons.description_outlined, p.contratUrl),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(feuille);
                    formulaireUtilisateur(context, profil: p);
                  },
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Modifier'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        p.suspendu ? Palette.vert : Palette.orFonce,
                    side: BorderSide(
                        color: p.suspendu ? Palette.vert : Palette.orFonce),
                  ),
                  onPressed: () async {
                    Navigator.pop(feuille);
                    await _basculerSuspension(context, etat, p);
                  },
                  icon: Icon(
                      p.suspendu
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 18),
                  label: Text(p.suspendu ? 'Réactiver' : 'Suspendre'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (p.id != etat.moi!.id)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Palette.rouge),
                  onPressed: () async {
                    Navigator.pop(feuille);
                    await _supprimer(context, etat, p);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  label: const Text('Supprimer cet espace'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _document(
      BuildContext context, String titre, IconData icone, String? url) {
    final present = url != null && url.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: present ? () => _ouvrirDocument(context, url) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: present
              ? Palette.bleu.withValues(alpha: 0.09)
              : Theme.of(context).dividerColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Icon(icone,
              size: 26,
              color: present ? Palette.bleu : Theme.of(context).hintColor),
          const SizedBox(height: 8),
          Text(titre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(present ? 'Appuyer pour voir' : 'Non fourni',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }

  Future<void> _ouvrirDocument(BuildContext context, String url) async {
    if (url.toLowerCase().endsWith('.pdf')) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBar(
            title: const Text('Document'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close_rounded)),
            ],
          ),
          Flexible(
              child: InteractiveViewer(
                  child: Image.network(url,
                      errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(30),
                            child: Vide('Impossible d’afficher ce document',
                                icone: Icons.broken_image_outlined),
                          )))),
        ]),
      ),
    );
  }

  Future<void> _basculerSuspension(
      BuildContext context, Etat etat, Profil p) async {
    final suspendre = !p.suspendu;
    final ok = await confirmer(
      context,
      titre: suspendre
          ? 'Suspendre ${p.nomComplet} ?'
          : 'Réactiver ${p.nomComplet} ?',
      texte: suspendre
          ? 'Cette personne pourra encore se connecter et consulter, mais ne pourra plus rien saisir ni pointer.'
          : 'Cette personne pourra de nouveau saisir et pointer.',
      ok: suspendre ? 'Suspendre' : 'Réactiver',
      danger: suspendre,
      icone: suspendre ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    if (!ok || !context.mounted) return;
    final e = await etat
        .agir(() => Api.majProfil(p.id, {'suspendu': suspendre}));
    if (context.mounted) {
      message(context,
          e ?? (suspendre ? 'Compte suspendu' : 'Compte réactivé'),
          erreur: e != null);
    }
  }

  Future<void> _supprimer(BuildContext context, Etat etat, Profil p) async {
    final ok = await confirmer(
      context,
      titre: 'Supprimer ${p.nomComplet} ?',
      texte:
          'Sa fiche et toutes ses saisies (productions, recettes, dépenses, '
          'pointages) seront effacées. Il ne pourra plus entrer dans l’application.\n\n'
          'Pour l’écarter sans rien perdre, suspendez-le plutôt.',
      ok: 'Supprimer définitivement',
      danger: true,
      icone: Icons.person_remove_rounded,
    );
    if (!ok || !context.mounted) return;
    final e = await etat.agir(() => Api.supprimerProfil(p.id));
    if (context.mounted) {
      message(context, e ?? 'Espace supprimé', erreur: e != null);
    }
  }
}
