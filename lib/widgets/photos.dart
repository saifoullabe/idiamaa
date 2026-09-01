import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/api.dart';
import 'communs.dart';

/// Les vignettes des photos d'un signalement, d'un rapport ou d'une fiche.
/// Un appui les ouvre en grand, et on passe de l'une à l'autre en glissant.
class GaleriePhotos extends StatelessWidget {
  final List<String> urls;
  final double taille;

  const GaleriePhotos(this.urls, {super.key, this.taille = 74});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < urls.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => ouvrirVisionneuse(context, urls, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                urls[i],
                width: taille,
                height: taille,
                fit: BoxFit.cover,
                loadingBuilder: (c, enfant, avancement) => avancement == null
                    ? enfant
                    : Squelette(hauteur: taille, largeur: taille, rayon: 12),
                errorBuilder: (_, _, _) => Container(
                  width: taille,
                  height: taille,
                  color: Theme.of(context).dividerColor,
                  child: Icon(Icons.broken_image_outlined,
                      color: Theme.of(context).hintColor),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// La photo en grand, sur fond noir, avec le zoom par pincement.
void ouvrirVisionneuse(BuildContext context, List<String> urls, int depart) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (c) => _Visionneuse(urls: urls, depart: depart),
  );
}

class _Visionneuse extends StatefulWidget {
  final List<String> urls;
  final int depart;

  const _Visionneuse({required this.urls, required this.depart});

  @override
  State<_Visionneuse> createState() => _VisionneuseState();
}

class _VisionneuseState extends State<_Visionneuse> {
  late final PageController _pages = PageController(initialPage: widget.depart);
  late int _courante = widget.depart;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _courante = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.network(
                widget.urls[i],
                fit: BoxFit.contain,
                loadingBuilder: (c, enfant, avancement) => avancement == null
                    ? enfant
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, _, _) => const Center(
                  child: Text('Image indisponible',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        if (widget.urls.length > 1)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 22),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text('${_courante + 1} / ${widget.urls.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Le bloc « ajouter des photos » des formulaires : appareil photo,
/// galerie, et les vignettes de ce qui a déjà été choisi.
class ChoixPhotos extends StatefulWidget {
  final List<FichierChoisi> photos;
  final VoidCallback auChangement;
  final String titre;
  final int maximum;

  const ChoixPhotos({
    super.key,
    required this.photos,
    required this.auChangement,
    this.titre = 'Photos',
    this.maximum = 6,
  });

  @override
  State<ChoixPhotos> createState() => _ChoixPhotosState();
}

class _ChoixPhotosState extends State<ChoixPhotos> {
  bool _occupe = false;

  Future<void> _prendre(ImageSource source) async {
    if (widget.photos.length >= widget.maximum) {
      message(context, '${widget.maximum} photos au maximum.', erreur: true);
      return;
    }
    setState(() => _occupe = true);
    try {
      // 70 % de qualité et 1600 px de large : l'image reste nette et
      // pèse ~200 Ko au lieu de 4 Mo. Sur une connexion faible, ça fait
      // la différence entre un envoi qui passe et un envoi qui échoue.
      final f = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (f != null) {
        widget.photos.add(FichierChoisi(await f.readAsBytes(), f.name));
        widget.auChangement();
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final couleur = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(widget.titre.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 8),
        Text('${widget.photos.length}/${widget.maximum}',
            style: Theme.of(context).textTheme.labelSmall),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _occupe ? null : () => _prendre(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 19),
            label: const Text('Prendre'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _occupe ? null : () => _prendre(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 19),
            label: const Text('Galerie'),
          ),
        ),
      ]),
      if (widget.photos.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.photos.length; i++)
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(widget.photos[i].octets,
                      width: 78, height: 78, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: () {
                      widget.photos.removeAt(i);
                      widget.auChangement();
                      setState(() {});
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Palette.rouge,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: const Icon(Icons.close_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ]),
          ],
        ),
      ],
      if (_occupe)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: couleur)),
            const SizedBox(width: 10),
            Text('Préparation de la photo…',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
    ]);
  }
}
