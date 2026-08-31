import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';

// ── Messages ─────────────────────────────────────────────────────────
void message(BuildContext context, String texte, {bool erreur = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(erreur ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(texte,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: erreur ? Palette.rouge : Palette.vertMoyen,
      duration: Duration(seconds: erreur ? 5 : 3),
    ));
}

Future<bool> confirmer(
  BuildContext context, {
  required String titre,
  required String texte,
  String ok = 'Confirmer',
  IconData icone = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(icone, size: 40, color: danger ? Palette.rouge : Palette.vert),
      title: Text(titre, textAlign: TextAlign.center),
      content: Text(texte,
          textAlign: TextAlign.center, style: Theme.of(c).textTheme.bodyMedium),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Palette.rouge)
              : null,
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Demande un nombre (prix, quantité) dans une boîte soignée.
Future<double?> demanderNombre(
  BuildContext context, {
  required String titre,
  required String sousTitre,
  String? valeurInitiale,
  String suffixe = '',
  IconData icone = Icons.calculate_rounded,
  Color? couleur,
}) async {
  final champ = TextEditingController(text: valeurInitiale ?? '');
  final c = couleur ?? Palette.vert;
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icone, size: 38, color: c),
      title: Text(titre, textAlign: TextAlign.center),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(sousTitre,
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: champ,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w800, color: c),
          decoration: InputDecoration(suffixText: suffixe),
        ),
      ]),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c),
          onPressed: () {
            final v = double.tryParse(champ.text.replaceAll(',', '.'));
            Navigator.pop(ctx, v);
          },
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

Future<String?> demanderTexte(
  BuildContext context, {
  required String titre,
  String indice = '',
  String ok = 'Valider',
}) async {
  final champ = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: TextField(
        controller: champ,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(hintText: indice),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, champ.text.trim()),
            child: Text(ok)),
      ],
    ),
  );
}

// ── Briques d'affichage ──────────────────────────────────────────────

/// Le titre d'une section, avec éventuellement un bouton à droite.
class TitreSection extends StatelessWidget {
  final String titre;
  final String? emoji;
  final Widget? action;
  final EdgeInsets marge;

  const TitreSection(this.titre,
      {super.key,
      this.emoji,
      this.action,
      this.marge = const EdgeInsets.fromLTRB(4, 22, 4, 12)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: marge,
      child: Row(children: [
        if (emoji != null) ...[
          Text(emoji!, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 8),
        ],
        Expanded(
            child: Text(titre, style: Theme.of(context).textTheme.titleMedium)),
        if (action != null) action!,
      ]),
    );
  }
}

/// Une carte avec un contenu libre — la brique de base de l'application.
class Bloc extends StatelessWidget {
  final Widget enfant;
  final EdgeInsets padding;
  final VoidCallback? auClic;
  final Color? fond;
  final Color? bordure;

  const Bloc({
    super.key,
    required this.enfant,
    this.padding = const EdgeInsets.all(16),
    this.auClic,
    this.fond,
    this.bordure,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: fond,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: bordure ??
              (theme.brightness == Brightness.dark
                  ? Colors.white10
                  : const Color(0xFFE2EAE0)),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: auClic,
        child: Padding(padding: padding, child: enfant),
      ),
    );
  }
}

/// Un chiffre-clé : libellé, valeur, et une couleur qui parle.
class CarteChiffre extends StatelessWidget {
  final String libelle;
  final String valeur;
  final String? complement;
  final Color couleur;
  final IconData icone;
  final VoidCallback? auClic;

  const CarteChiffre({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.couleur,
    required this.icone,
    this.complement,
    this.auClic,
  });

  @override
  Widget build(BuildContext context) {
    return Bloc(
      auClic: auClic,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icone, size: 16, color: couleur),
            ),
            const Spacer(),
            if (auClic != null)
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Theme.of(context).hintColor),
          ]),
          const SizedBox(height: 11),
          Text(libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valeur,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: couleur)),
          ),
          if (complement != null) ...[
            const SizedBox(height: 2),
            Text(complement!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Grille de chiffres-clés qui s'adapte à la largeur de l'écran.
class GrilleChiffres extends StatelessWidget {
  final List<Widget> cartes;
  final double largeurMin;

  const GrilleChiffres(this.cartes, {super.key, this.largeurMin = 165});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final colonnes = (c.maxWidth / largeurMin).floor().clamp(2, 4);
      return GridView.count(
        crossAxisCount: colonnes,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.28,
        children: cartes,
      );
    });
  }
}

/// La pastille qui dit où en est une saisie.
class PuceStatut extends StatelessWidget {
  final String statut;
  final bool compact;

  const PuceStatut(this.statut, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = Statut.couleur(statut);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Statut.icone(statut), size: 13, color: c),
        if (!compact) ...[
          const SizedBox(width: 5),
          Text(Statut.libelle(statut),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ],
      ]),
    );
  }
}

class Etiquette extends StatelessWidget {
  final String texte;
  final Color couleur;
  final IconData? icone;

  const Etiquette(this.texte,
      {super.key, this.couleur = Palette.gris, this.icone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icone != null) ...[
          Icon(icone, size: 12, color: couleur),
          const SizedBox(width: 5),
        ],
        Text(texte,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur)),
      ]),
    );
  }
}

/// Ce qu'on affiche quand il n'y a rien à afficher.
class Vide extends StatelessWidget {
  final IconData icone;
  final String texte;
  final String? action;
  final VoidCallback? auClic;

  const Vide(this.texte,
      {super.key,
      this.icone = Icons.inbox_rounded,
      this.action,
      this.auClic});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Column(children: [
        Icon(icone, size: 40, color: Theme.of(context).hintColor),
        const SizedBox(height: 12),
        Text(texte,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).hintColor,
                fontWeight: FontWeight.w600)),
        if (action != null) ...[
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: auClic, child: Text(action!)),
        ],
      ]),
    );
  }
}

/// Un bandeau d'information ou d'alerte, pleine largeur.
class Bandeau extends StatelessWidget {
  final String titre;
  final String? texte;
  final Color couleur;
  final IconData icone;
  final Widget? action;
  final VoidCallback? auClic;

  const Bandeau({
    super.key,
    required this.titre,
    this.texte,
    this.couleur = Palette.or,
    this.icone = Icons.info_outline_rounded,
    this.action,
    this.auClic,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: couleur.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: auClic,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: couleur, width: 4)),
          ),
          child: Row(children: [
            Icon(icone, color: couleur, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: couleur)),
                  if (texte != null) ...[
                    const SizedBox(height: 2),
                    Text(texte!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
            if (action == null && auClic != null)
              Icon(Icons.chevron_right_rounded, color: couleur),
          ]),
        ),
      ),
    );
  }
}

/// Une ligne « libellé — valeur » dans une fiche.
class LigneInfo extends StatelessWidget {
  final String libelle;
  final String valeur;
  final IconData? icone;

  const LigneInfo(this.libelle, this.valeur, {super.key, this.icone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icone != null) ...[
          Icon(icone, size: 15, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 128,
          child: Text(libelle, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(valeur.isEmpty ? '—' : valeur,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// L'avatar rond d'une personne.
class Pastille extends StatelessWidget {
  final String nom;
  final String? photoUrl;
  final double taille;
  final Color? couleur;

  const Pastille(this.nom,
      {super.key, this.photoUrl, this.taille = 42, this.couleur});

  @override
  Widget build(BuildContext context) {
    final c = couleur ?? Palette.vert;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(photoUrl!,
            width: taille,
            height: taille,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _lettres(c)),
      );
    }
    return _lettres(c);
  }

  Widget _lettres(Color c) => Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [c, Color.lerp(c, Colors.black, 0.28)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(initiales(nom),
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: taille * 0.36)),
      );
}

/// La barre de remplissage d'un stock.
class Jauge extends StatelessWidget {
  final int pourcent;
  final Color couleur;

  const Jauge(this.pourcent, {super.key, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pourcent / 100),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => LinearProgressIndicator(
          value: v,
          minHeight: 9,
          backgroundColor: couleur.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(couleur),
        ),
      ),
    );
  }
}

/// Le squelette gris affiché pendant le chargement.
class Squelette extends StatefulWidget {
  final double hauteur;
  final double? largeur;
  final double rayon;

  const Squelette({super.key, this.hauteur = 80, this.largeur, this.rayon = 18});

  @override
  State<Squelette> createState() => _SqueletteState();
}

class _SqueletteState extends State<Squelette>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? Colors.white10
        : const Color(0xFFE7EEE5);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.hauteur,
        width: widget.largeur ?? double.infinity,
        decoration: BoxDecoration(
          color: Color.lerp(base, base.withValues(alpha: 0.35), _c.value),
          borderRadius: BorderRadius.circular(widget.rayon),
        ),
      ),
    );
  }
}

class ChargementPage extends StatelessWidget {
  const ChargementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Row(children: [
          Expanded(child: Squelette(hauteur: 96)),
          SizedBox(width: 10),
          Expanded(child: Squelette(hauteur: 96)),
        ]),
        SizedBox(height: 10),
        Row(children: [
          Expanded(child: Squelette(hauteur: 96)),
          SizedBox(width: 10),
          Expanded(child: Squelette(hauteur: 96)),
        ]),
        SizedBox(height: 18),
        Squelette(hauteur: 160),
        SizedBox(height: 12),
        Squelette(hauteur: 120),
      ],
    );
  }
}

/// Le montant d'une ligne, en gros et coloré.
class Montant extends StatelessWidget {
  final int valeur;
  final bool negatif;
  final double taille;

  const Montant(this.valeur,
      {super.key, this.negatif = false, this.taille = 16});

  @override
  Widget build(BuildContext context) {
    final c = negatif ? Palette.rouge : Palette.vert;
    return Text('${negatif ? '-' : ''}${gnf(valeur)}',
        style: TextStyle(
            fontSize: taille,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: c));
  }
}
