import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constantes.dart';
import '../core/theme.dart';
import '../data/etat.dart';

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _login = TextEditingController();
  final _motDePasse = TextEditingController();
  final _formulaire = GlobalKey<FormState>();
  bool _cache = true;
  bool _occupe = false;
  bool _seSouvenir = true;
  String _role = Role.admin;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final dernier = p.getString('dernier_login');
      final dernierRole = p.getString('dernier_role');
      setState(() {
        if (dernier != null) _login.text = dernier;
        if (dernierRole != null) _role = dernierRole;
      });
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _entrer() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final probleme = await context
        .read<Etat>()
        .connexion(_login.text.trim(), _motDePasse.text);
    if (!mounted) return;
    if (probleme == null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('dernier_role', _role);
      if (_seSouvenir) {
        await p.setString('dernier_login', _login.text.trim());
      } else {
        await p.remove('dernier_login');
      }
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _erreur = probleme;
    });
  }

  Color get _couleur => Palette.duRole(_role);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF071A07), Palette.vert, Color(0xFF14401A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Form(
                      key: _formulaire,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _entete(),
                          const SizedBox(height: 22),
                          _onglets(),
                          const SizedBox(height: 20),
                          if (_erreur != null) _messageErreur(),
                          _libelle('Identifiant'),
                          TextFormField(
                            controller: _login,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: switch (_role) {
                                Role.admin => 'ex : admin',
                                Role.gerant => 'ex : dubreka',
                                _ => 'ex : fermier1',
                              },
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Entrez votre identifiant'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          _libelle('Mot de passe'),
                          TextFormField(
                            controller: _motDePasse,
                            obscureText: _cache,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _entrer(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: IconButton(
                                tooltip: _cache ? 'Afficher' : 'Masquer',
                                icon: Icon(_cache
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _cache = !_cache),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Entrez votre mot de passe'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 54,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _couleur,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _occupe ? null : _entrer,
                              child: _occupe
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white))
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text('Connexion',
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800)),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded,
                                            size: 20),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _aide(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entete() => Column(children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _couleur.withValues(alpha: 0.10),
          ),
          alignment: Alignment.center,
          child: const Text('🐔', style: TextStyle(fontSize: 38)),
        ),
        const SizedBox(height: 14),
        Text('IDIAMA Agro',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Palette.vert)),
        const SizedBox(height: 3),
        const Text('Gestion des Fermes Avicoles',
            style: TextStyle(fontSize: 13, color: Palette.gris)),
      ]);

  /// Les trois espaces. Le choix ne décide de rien — c'est le compte qui
  /// dit qui vous êtes — mais il habille l'écran et guide la saisie.
  Widget _onglets() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4EF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        _onglet(Role.admin, '👑', 'Admin'),
        _onglet(Role.gerant, '🏚️', 'Gérant'),
        _onglet(Role.fermier, '👨‍🌾', 'Fermier'),
      ]),
    );
  }

  Widget _onglet(String role, String emoji, String texte) {
    final choisi = _role == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: choisi ? Palette.duRole(role) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(texte,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: choisi ? Colors.white : Palette.gris,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _libelle(String texte) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 7),
        child: Text(texte.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Palette.gris)),
      );

  Widget _aide() => Column(children: [
        Row(children: [
          Transform.scale(
            scale: 0.9,
            child: Checkbox(
              value: _seSouvenir,
              activeColor: _couleur,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() => _seSouvenir = v ?? true),
            ),
          ),
          const Expanded(
            child: Text('Retenir mon identifiant',
                style: TextStyle(fontSize: 12.5, color: Palette.gris)),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4EF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Identifiant ou mot de passe oublié ?\n'
            'Demandez à votre administrateur : lui seul peut les redonner.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: Palette.gris),
          ),
        ),
      ]);

  Widget _messageErreur() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Palette.rouge.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.rouge.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Palette.rouge, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_erreur!,
                style: const TextStyle(
                    color: Palette.rouge,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
