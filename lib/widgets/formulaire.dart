import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// Ouvre un formulaire en feuille montante, qui remonte au-dessus du
/// clavier et ne dépasse jamais la hauteur de l'écran.
Future<bool> ouvrirFormulaire(
  BuildContext context, {
  required String titre,
  required String emoji,
  required List<Widget> Function(BuildContext, VoidCallback rafraichir) champs,
  required Future<String?> Function() enregistrer,
  String libelleBouton = 'Enregistrer',
  Color? couleur,
}) async {
  final resultat = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (feuille) => _CorpsFormulaire(
      titre: titre,
      emoji: emoji,
      champs: champs,
      enregistrer: enregistrer,
      libelleBouton: libelleBouton,
      couleur: couleur,
    ),
  );
  return resultat ?? false;
}

class _CorpsFormulaire extends StatefulWidget {
  final String titre;
  final String emoji;
  final List<Widget> Function(BuildContext, VoidCallback) champs;
  final Future<String?> Function() enregistrer;
  final String libelleBouton;
  final Color? couleur;

  const _CorpsFormulaire({
    required this.titre,
    required this.emoji,
    required this.champs,
    required this.enregistrer,
    required this.libelleBouton,
    this.couleur,
  });

  @override
  State<_CorpsFormulaire> createState() => _CorpsFormulaireState();
}

class _CorpsFormulaireState extends State<_CorpsFormulaire> {
  bool _occupe = false;
  String? _erreur;

  Future<void> _valider() async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final probleme = await widget.enregistrer();
    if (!mounted) return;
    if (probleme == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _occupe = false;
        _erreur = probleme;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clavier = MediaQuery.of(context).viewInsets.bottom;
    final couleur = widget.couleur ?? Theme.of(context).colorScheme.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: clavier),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 8),
              child: Row(children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 21)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.titre,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erreur != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Palette.rouge.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(13),
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
                      ),
                    ...widget.champs(context, () => setState(() {})),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _occupe ? null : () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: couleur),
                      onPressed: _occupe ? null : _valider,
                      icon: _occupe
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text(
                          _occupe ? 'Patientez…' : widget.libelleBouton),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Champs prêts à l'emploi ──────────────────────────────────────────

class ChampTexte extends StatelessWidget {
  final TextEditingController controleur;
  final String libelle;
  final String? indice;
  final IconData? icone;
  final int lignes;
  final TextInputType? clavier;
  final bool obligatoire;

  const ChampTexte(
    this.controleur, {
    super.key,
    required this.libelle,
    this.indice,
    this.icone,
    this.lignes = 1,
    this.clavier,
    this.obligatoire = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controleur,
        maxLines: lignes,
        minLines: 1,
        keyboardType: clavier,
        textCapitalization: lignes > 1
            ? TextCapitalization.sentences
            : TextCapitalization.words,
        decoration: InputDecoration(
          labelText: obligatoire ? '$libelle *' : libelle,
          hintText: indice,
          prefixIcon: icone == null ? null : Icon(icone, size: 20),
          alignLabelWithHint: lignes > 1,
        ),
      ),
    );
  }
}

/// Champ pour un montant ou une quantité : clavier chiffres,
/// et le montant se relit en toutes lettres sous le champ.
class ChampNombre extends StatefulWidget {
  final TextEditingController controleur;
  final String libelle;
  final String? indice;
  final String suffixe;
  final bool argent;
  final bool obligatoire;
  final VoidCallback? auChangement;
  final IconData? icone;

  const ChampNombre(
    this.controleur, {
    super.key,
    required this.libelle,
    this.indice,
    this.suffixe = '',
    this.argent = false,
    this.obligatoire = false,
    this.auChangement,
    this.icone,
  });

  @override
  State<ChampNombre> createState() => _ChampNombreState();
}

class _ChampNombreState extends State<ChampNombre> {
  @override
  Widget build(BuildContext context) {
    final valeur = double.tryParse(widget.controleur.text.replaceAll(',', '.'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: widget.controleur,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: widget.argent
              ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)
              : null,
          onChanged: (_) {
            setState(() {});
            widget.auChangement?.call();
          },
          decoration: InputDecoration(
            labelText:
                widget.obligatoire ? '${widget.libelle} *' : widget.libelle,
            hintText: widget.indice,
            prefixIcon: widget.icone == null
                ? null
                : Icon(widget.icone, size: 20),
            suffixText: widget.argent ? 'GNF' : widget.suffixe,
          ),
        ),
        if (widget.argent && valeur != null && valeur > 0)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 5),
            child: Text(gnf(valeur),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Palette.vertMoyen)),
          ),
      ]),
    );
  }
}

class ChampListe<T> extends StatelessWidget {
  final T? valeur;
  final List<DropdownMenuItem<T>> options;
  final String libelle;
  final ValueChanged<T?> auChangement;
  final IconData? icone;

  const ChampListe({
    super.key,
    required this.valeur,
    required this.options,
    required this.libelle,
    required this.auChangement,
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        initialValue: valeur,
        isExpanded: true,
        items: options,
        onChanged: auChangement,
        decoration: InputDecoration(
          labelText: libelle,
          prefixIcon: icone == null ? null : Icon(icone, size: 20),
        ),
      ),
    );
  }
}

class ChampDate extends StatelessWidget {
  final DateTime valeur;
  final String libelle;
  final ValueChanged<DateTime> auChangement;

  const ChampDate({
    super.key,
    required this.valeur,
    required this.libelle,
    required this.auChangement,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: valeur,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            locale: const Locale('fr', 'FR'),
          );
          if (d != null) auChangement(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: libelle,
            prefixIcon: const Icon(Icons.event_rounded, size: 20),
          ),
          child: Text(jour(valeur),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Le petit titre qui sépare deux groupes de champs.
class SousTitreFormulaire extends StatelessWidget {
  final String texte;
  const SousTitreFormulaire(this.texte, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(children: [
        Text(texte.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
      ]),
    );
  }
}
