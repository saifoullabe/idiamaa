import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Affiché si l'adresse Supabase n'a pas encore été renseignée.
/// Mieux vaut une explication claire qu'un écran blanc.
class ReglageManquant extends StatelessWidget {
  const ReglageManquant({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF071A07), Palette.vert],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🐔', style: TextStyle(fontSize: 46)),
                  const SizedBox(height: 12),
                  Text('IDIAMA Agro',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 14),
                  Text(
                    'L’application n’est pas encore reliée à sa base de données.\n\n'
                    'Il manque l’adresse du projet Supabase et sa clé publique '
                    '(Project Settings → API).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
