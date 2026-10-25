import 'package:flutter/material.dart';

import '../data/lien_fichier.dart';

/// Une image du coffre, affichée par une adresse signée.
///
/// Remplace Image.network partout où l'on montre un fichier envoyé
/// depuis l'application : le coffre n'est plus public, donc l'adresse
/// enregistrée en base ne suffit plus à l'ouvrir.
///
/// Les paramètres portent les mêmes noms que ceux d'Image.network, pour
/// que le remplacement ne change rien d'autre aux écrans.
class ImageProtegee extends StatefulWidget {
  final String adresse;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  const ImageProtegee(
    this.adresse, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  State<ImageProtegee> createState() => _ImageProtegeeState();
}

class _ImageProtegeeState extends State<ImageProtegee> {
  late Future<String> _lien;

  @override
  void initState() {
    super.initState();
    // Dans initState, pas dans build : sinon la signature serait
    // redemandée à chaque redessin, donc à chaque défilement.
    _lien = LienFichier.affichable(widget.adresse);
  }

  @override
  void didUpdateWidget(ImageProtegee ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.adresse != widget.adresse) {
      _lien = LienFichier.affichable(widget.adresse);
    }
  }

  /// Une seule reprise : l'adresse signée vit une heure, et un widget
  /// qui vit plus longtemps (la pastille de la barre du haut) finit par
  /// en tenir une périmée. Quand le téléphone vide son cache d'images,
  /// l'image repart alors sur une adresse morte — sans cette reprise,
  /// elle disparaissait définitivement.
  bool _reprise = false;

  Widget _attente(BuildContext c) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _refuse(BuildContext c) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: Icon(Icons.lock_outline_rounded,
              size: 18, color: Theme.of(c).hintColor),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _lien,
      builder: (c, instantane) {
        if (instantane.hasError) {
          // Refusé par la base : ce n'est pas une panne, et le cadenas
          // le dit mieux qu'une image cassée.
          if (instantane.error is LienRefuse) return _refuse(c);
          return widget.errorBuilder?.call(
                  c, instantane.error!, instantane.stackTrace) ??
              _attente(c);
        }
        if (!instantane.hasData) return _attente(c);
        return Image.network(
          instantane.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: (ec, erreur, pile) {
            if (!_reprise) {
              _reprise = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _lien =
                      LienFichier.affichable(widget.adresse, forcer: true));
                }
              });
              return _attente(ec);
            }
            return widget.errorBuilder?.call(ec, erreur, pile) ??
                SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: Icon(Icons.broken_image_outlined,
                      color: Theme.of(ec).hintColor),
                );
          },
        );
      },
    );
  }
}
