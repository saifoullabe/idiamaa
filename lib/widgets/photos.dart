import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';
import '../data/api.dart';
import 'communs.dart';

/// Photo ou vidéo ? On le déduit du nom du fichier — c'est suffisant,
/// et ça évite de traîner une colonne de plus dans la base.
bool estUneVideo(String nomOuUrl) {
  final n = nomOuUrl.toLowerCase().split('?').first;
  return n.endsWith('.mp4') ||
      n.endsWith('.mov') ||
      n.endsWith('.3gp') ||
      n.endsWith('.avi') ||
      n.endsWith('.mkv') ||
      n.endsWith('.webm');
}

/// Les vignettes des photos et vidéos d'un signalement, d'un rapport ou
/// d'une fiche. Un appui les ouvre en grand ; on passe de l'une à l'autre
/// en glissant.
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
              child: estUneVideo(urls[i])
                  ? Container(
                      width: taille,
                      height: taille,
                      color: Colors.black87,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 30),
                          SizedBox(height: 3),
                          Text('Vidéo',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    )
                  : Image.network(
                      urls[i],
                      width: taille,
                      height: taille,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, enfant, avancement) =>
                          avancement == null
                              ? enfant
                              : Squelette(
                                  hauteur: taille,
                                  largeur: taille,
                                  rayon: 12),
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

/// La photo en grand ou la vidéo, sur fond noir, avec le zoom au pincement.
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
          itemBuilder: (_, i) => estUneVideo(widget.urls[i])
              ? _LecteurVideo(url: widget.urls[i])
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      widget.urls[i],
                      fit: BoxFit.contain,
                      loadingBuilder: (c, enfant, avancement) =>
                          avancement == null
                              ? enfant
                              : const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white)),
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

class _LecteurVideo extends StatefulWidget {
  final String url;
  const _LecteurVideo({required this.url});

  @override
  State<_LecteurVideo> createState() => _LecteurVideoState();
}

class _LecteurVideoState extends State<_LecteurVideo> {
  VideoPlayerController? _lecteur;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _lecteur = c;
    c.initialize().then((_) {
      if (mounted) setState(() {});
      c.play();
    }).catchError((e) {
      if (mounted) setState(() => _erreur = 'Vidéo illisible');
    });
  }

  @override
  void dispose() {
    _lecteur?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) {
      return Center(
        child: Text(_erreur!, style: const TextStyle(color: Colors.white70)),
      );
    }
    final c = _lecteur;
    if (c == null || !c.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
        VideoProgressIndicator(c, allowScrubbing: true),
        const SizedBox(height: 8),
        IconButton(
          iconSize: 46,
          color: Colors.white,
          icon: Icon(c.value.isPlaying
              ? Icons.pause_circle_filled_rounded
              : Icons.play_circle_fill_rounded),
          onPressed: () => setState(
              () => c.value.isPlaying ? c.pause() : c.play()),
        ),
      ]),
    );
  }
}

/// Le bloc « ajouter des photos ou une vidéo » des formulaires.
class ChoixPhotos extends StatefulWidget {
  final List<FichierChoisi> photos;
  final VoidCallback auChangement;
  final String titre;
  final int maximum;
  final bool video;

  const ChoixPhotos({
    super.key,
    required this.photos,
    required this.auChangement,
    this.titre = 'Photos',
    this.maximum = 6,
    this.video = true,
  });

  @override
  State<ChoixPhotos> createState() => _ChoixPhotosState();
}

class _ChoixPhotosState extends State<ChoixPhotos> {
  bool _occupe = false;

  bool get _plein => widget.photos.length >= widget.maximum;

  Future<void> _prendrePhoto(ImageSource source) async {
    if (_plein) {
      message(context, '${widget.maximum} fichiers au maximum.', erreur: true);
      return;
    }
    setState(() => _occupe = true);
    try {
      // 70 % de qualité et 1600 px de large : l'image reste nette et
      // pèse ~200 Ko au lieu de 4 Mo. Sur une connexion faible, ça fait
      // la différence entre un envoi qui passe et un envoi qui échoue.
      final f = await ImagePicker()
          .pickImage(source: source, imageQuality: 70, maxWidth: 1600);
      if (f != null) {
        widget.photos.add(FichierChoisi(await f.readAsBytes(), f.name));
        widget.auChangement();
      }
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _prendreVideo(ImageSource source) async {
    if (_plein) {
      message(context, '${widget.maximum} fichiers au maximum.', erreur: true);
      return;
    }
    setState(() => _occupe = true);
    try {
      // 30 secondes maximum : une vidéo d'une minute pèse 60 Mo et ne
      // partira jamais depuis une ferme. 30 s suffisent à montrer un
      // comportement anormal ou l'état d'un bâtiment.
      final f = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
        preferredCameraDevice: CameraDevice.rear,
      );
      if (f == null) return;
      final octets = await f.readAsBytes();
      if (octets.lengthInBytes > 25 * 1024 * 1024) {
        if (mounted) {
          message(
              context,
              'Vidéo trop lourde (${(octets.lengthInBytes / 1048576).round()} Mo). '
              'Filmez plus court.',
              erreur: true);
        }
        return;
      }
      widget.photos.add(FichierChoisi(octets, f.name));
      widget.auChangement();
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
            onPressed:
                _occupe ? null : () => _prendrePhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 19),
            label: const Text('Photo'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _occupe ? null : () => _prendrePhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 19),
            label: const Text('Galerie'),
          ),
        ),
      ]),
      if (widget.video) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.bleu,
                  side: const BorderSide(color: Palette.bleu)),
              onPressed:
                  _occupe ? null : () => _prendreVideo(ImageSource.camera),
              icon: const Icon(Icons.videocam_outlined, size: 19),
              label: const Text('Filmer 30 s'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.bleu,
                  side: const BorderSide(color: Palette.bleu)),
              onPressed:
                  _occupe ? null : () => _prendreVideo(ImageSource.gallery),
              icon: const Icon(Icons.video_library_outlined, size: 19),
              label: const Text('Une vidéo'),
            ),
          ),
        ]),
      ],
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
                  child: estUneVideo(widget.photos[i].nom)
                      ? Container(
                          width: 78,
                          height: 78,
                          color: Colors.black87,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.movie_rounded,
                                  color: Colors.white, size: 26),
                              const SizedBox(height: 3),
                              Text(
                                  '${(widget.photos[i].octets.lengthInBytes / 1048576).toStringAsFixed(1)} Mo',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 9.5)),
                            ],
                          ),
                        )
                      : Image.memory(widget.photos[i].octets,
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
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: couleur)),
            const SizedBox(width: 10),
            Text('Préparation du fichier…',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
    ]);
  }
}
