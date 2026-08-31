
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/api.dart';
import '../data/etat.dart';
import '../widgets/communs.dart';

/// Ce que chacun peut changer sur lui-même : sa photo, son téléphone,
/// son mot de passe. Ni son rôle, ni sa ferme — c'est l'admin qui décide.
class EcranMonCompte extends StatefulWidget {
  const EcranMonCompte({super.key});

  @override
  State<EcranMonCompte> createState() => _EcranMonCompteState();
}

class _EcranMonCompteState extends State<EcranMonCompte> {
  final _tel = TextEditingController();
  final _tel2 = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  FichierChoisi? _photo;
  bool _cache = true;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    final moi = context.read<Etat>().moi;
    _tel.text = moi?.tel ?? '';
    _tel2.text = moi?.tel2 ?? '';
  }

  @override
  void dispose() {
    _tel.dispose();
    _tel2.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = context.watch<Etat>();
    final moi = etat.moi;
    if (moi == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Center(
            child: Column(children: [
              Stack(children: [
                Pastille(moi.nomComplet,
                    photoUrl: _photo == null ? moi.photoUrl : null,
                    taille: 104,
                    couleur: Palette.duRole(moi.role)),
                if (_photo != null)
                  ClipOval(
                    child: Image.memory(_photo!.octets,
                        width: 104, height: 104, fit: BoxFit.cover),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final f = await ImagePicker().pickImage(
                            source: ImageSource.gallery, imageQuality: 80);
                        if (f == null) return;
                        final octets = await f.readAsBytes();
                        if (mounted) {
                          setState(
                              () => _photo = FichierChoisi(octets, f.name));
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.photo_camera_rounded,
                            size: 17, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(moi.nomComplet,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                  '${Role.emoji(moi.role)} ${Role.libelle(moi.role)}'
                  '${moi.fermeId != null ? ' · ${etat.nomFerme(moi.fermeId)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          const TitreSection('Mon identifiant'),
          Bloc(
            enfant: Column(children: [
              LigneInfo('Identifiant', moi.login, icone: Icons.key_rounded),
              LigneInfo('Compte créé le', jour(moi.creeLe),
                  icone: Icons.event_available_rounded),
              const SizedBox(height: 6),
              const Bandeau(
                titre: 'L’identifiant ne change pas',
                texte:
                    'C’est lui qui relie toutes vos saisies. Seul l’administrateur peut en créer un nouveau.',
                couleur: Palette.bleu,
              ),
            ]),
          ),
          const TitreSection('Mes coordonnées'),
          Bloc(
            enfant: Column(children: [
              TextField(
                controller: _tel,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _tel2,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone 2',
                  prefixIcon: Icon(Icons.phone_iphone_outlined),
                ),
              ),
            ]),
          ),
          const TitreSection('Nouveau mot de passe'),
          Bloc(
            enfant: Column(children: [
              TextField(
                controller: _motDePasse,
                obscureText: _cache,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  helperText: 'Laissez vide pour le garder tel quel',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_cache
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _cache = !_cache),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmation,
                obscureText: _cache,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: _occupe
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.3, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: Text(_occupe ? 'Patientez…' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _enregistrer() async {
    final etat = context.read<Etat>();
    if (_motDePasse.text.isNotEmpty) {
      if (_motDePasse.text.length < 6) {
        message(context, 'Le mot de passe doit faire au moins 6 caractères.',
            erreur: true);
        return;
      }
      if (_motDePasse.text != _confirmation.text) {
        message(context, 'Les deux mots de passe ne sont pas identiques.',
            erreur: true);
        return;
      }
    }

    setState(() => _occupe = true);
    final e = await etat.agir(() async {
      String? lien;
      if (_photo != null) lien = await Api.envoyerFichier(_photo!, 'photos');
      await Api.majProfil(etat.moi!.id, {
        'tel': _tel.text.trim(),
        'tel2': _tel2.text.trim(),
        if (lien != null) 'photo_url': lien,
      });
      if (_motDePasse.text.isNotEmpty) {
        await Api.changerMotDePasse(_motDePasse.text);
      }
    });
    if (!mounted) return;
    setState(() => _occupe = false);
    if (e == null) {
      _motDePasse.clear();
      _confirmation.clear();
      _photo = null;
    }
    message(context, e ?? 'Modifications enregistrées', erreur: e != null);
  }
}
