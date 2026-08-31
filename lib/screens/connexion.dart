import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String? _erreur;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final dernier = p.getString('dernier_login');
      if (dernier != null && mounted) setState(() => _login.text = dernier);
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
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _entete(),
                    const SizedBox(height: 26),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                        child: Form(
                          key: _formulaire,
                          child: Column(children: [
                            if (_erreur != null) _messageErreur(),
                            TextFormField(
                              controller: _login,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Identifiant',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Entrez votre identifiant'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _motDePasse,
                              obscureText: _cache,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _entrer(),
                              decoration: InputDecoration(
                                labelText: 'Mot de passe',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
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
                            const SizedBox(height: 6),
                            Row(children: [
                              Checkbox(
                                value: _seSouvenir,
                                onChanged: (v) =>
                                    setState(() => _seSouvenir = v ?? true),
                              ),
                              const Expanded(
                                child: Text('Retenir mon identifiant',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _occupe ? null : _entrer,
                                icon: _occupe
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white))
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                    _occupe ? 'Connexion…' : 'Se connecter'),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Gestion des fermes avicoles · Guinée',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11.5),
                    ),
                  ],
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
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text('🐔', style: TextStyle(fontSize: 42)),
        ),
        const SizedBox(height: 16),
        const Text('IDIAMA Agro',
            style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8)),
        const SizedBox(height: 4),
        Text('Fermes avicoles · Production & Finances',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72), fontSize: 12.5)),
      ]);

  Widget _messageErreur() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Palette.rouge.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Palette.rouge.withValues(alpha: 0.35)),
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
