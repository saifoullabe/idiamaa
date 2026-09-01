import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/modeles.dart';
import 'format.dart';

/// Les factures et relevés d'IDIAMA, en PDF.
/// Le document est fabriqué sur le téléphone : il part par WhatsApp,
/// s'imprime ou s'enregistre, sans passer par un serveur.
class Facture {
  static const _vert = PdfColor.fromInt(0xFF1B5E20);
  static const _or = PdfColor.fromInt(0xFFF9A825);
  static const _gris = PdfColor.fromInt(0xFF607D8B);
  static const _clair = PdfColor.fromInt(0xFFF1F4EF);

  /// La facture d'un achat.
  static Future<void> vente({
    required Vente v,
    required Client client,
    required String nomFerme,
    required String villeFerme,
    required String vendeur,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _entete(nomFerme, villeFerme, v.reference, v.date),
            pw.SizedBox(height: 26),
            _blocClient(client),
            pw.SizedBox(height: 22),
            _tableauLigne(v),
            pw.SizedBox(height: 18),
            _total(v),
            pw.SizedBox(height: 22),
            if (v.note.isNotEmpty) ...[
              pw.Text('Note', style: _petit()),
              pw.SizedBox(height: 4),
              pw.Text(v.note, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 18),
            ],
            _mentionPaiement(v),
            pw.Spacer(),
            _pied(vendeur),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'facture-${v.reference}.pdf',
    );
  }

  /// Le relevé de tous les achats d'un client.
  static Future<void> releve({
    required Client client,
    required List<Vente> ventes,
    required String nomFerme,
    required String villeFerme,
  }) async {
    final doc = pw.Document();
    final total = ventes.fold<int>(0, (s, v) => s + v.montant);
    final impaye = ventes
        .where((v) => !v.paye)
        .fold<int>(0, (s, v) => s + v.montant);
    final alveoles = ventes.fold<int>(0, (s, v) => s + v.nbAlveoles);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _entete(nomFerme, villeFerme, 'RELEVÉ DE COMPTE', DateTime.now()),
          pw.SizedBox(height: 26),
          _blocClient(client),
          pw.SizedBox(height: 22),
          pw.Table(
            border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(color: _clair, width: 1)),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2.4),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2.4),
              5: const pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _vert),
                children: [
                  _th('Date'),
                  _th('Facture'),
                  _th('Alvéoles', droite: true),
                  _th('Prix/alv.', droite: true),
                  _th('Montant', droite: true),
                  _th('État', droite: true),
                ],
              ),
              for (final v in ventes)
                pw.TableRow(children: [
                  _td(jour(v.date)),
                  _td(v.reference),
                  _td('${v.nbAlveoles}', droite: true),
                  _td(nb(v.prixAlveole), droite: true),
                  _td(nb(v.montant), droite: true, gras: true),
                  _td(v.paye ? 'Payé' : 'Impayé', droite: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _clair,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(children: [
              _ligneTotal('Nombre d’achats', '${ventes.length}'),
              _ligneTotal('Alvéoles achetées',
                  '${nb(alveoles)}  (${nb(alveoles * 30)} œufs)'),
              _ligneTotal('Total facturé', '${nb(total)} GNF', gras: true),
              if (impaye > 0)
                _ligneTotal('Reste à payer', '${nb(impaye)} GNF',
                    gras: true, alerte: true),
            ]),
          ),
          pw.SizedBox(height: 26),
          _pied(''),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'releve-${client.nom.replaceAll(' ', '-')}.pdf',
    );
  }

  // ── Les briques du document ────────────────────────────────────────
  static pw.Widget _entete(
      String ferme, String ville, String reference, DateTime? date) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('IDIAMA AGRO',
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _vert)),
          pw.SizedBox(height: 3),
          pw.Text(ferme, style: pw.TextStyle(fontSize: 12, color: _gris)),
          if (ville.isNotEmpty)
            pw.Text(ville, style: pw.TextStyle(fontSize: 10, color: _gris)),
        ]),
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _clair,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(reference,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _vert)),
                pw.SizedBox(height: 2),
                pw.Text(jour(date),
                    style: pw.TextStyle(fontSize: 10, color: _gris)),
              ]),
        ),
      ],
    );
  }

  static pw.Widget _blocClient(Client c) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _clair, width: 2),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CLIENT', style: _petit()),
              pw.SizedBox(height: 5),
              pw.Text(c.nom,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(_libelleType(c.type),
                  style: pw.TextStyle(fontSize: 10, color: _gris)),
              if (c.telephone.isNotEmpty)
                pw.Text('Tél. ${c.telephone}'
                    '${c.telephone2.isEmpty ? '' : ' / ${c.telephone2}'}',
                    style: const pw.TextStyle(fontSize: 10)),
              if (c.adresse.isNotEmpty)
                pw.Text(c.adresse, style: const pw.TextStyle(fontSize: 10)),
            ]),
      );

  static pw.Widget _tableauLigne(Vente v) => pw.Table(
        border: pw.TableBorder.symmetric(
            inside: const pw.BorderSide(color: _clair, width: 1)),
        columnWidths: {
          0: const pw.FlexColumnWidth(4),
          1: const pw.FlexColumnWidth(1.6),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(2.2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _vert),
            children: [
              _th('Désignation'),
              _th('Quantité', droite: true),
              _th('Prix unitaire', droite: true),
              _th('Montant', droite: true),
            ],
          ),
          pw.TableRow(children: [
            _td('Alvéoles d’œufs (30 œufs par alvéole)\n'
                'soit ${nb(v.oeufs)} œufs'),
            _td('${v.nbAlveoles}', droite: true),
            _td('${nb(v.prixAlveole)} GNF', droite: true),
            _td('${nb(v.montant)} GNF', droite: true, gras: true),
          ]),
        ],
      );

  static pw.Widget _total(Vente v) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Container(
            width: 240,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _vert,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL À PAYER',
                    style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('${nb(v.montant)} GNF',
                    style: pw.TextStyle(
                        fontSize: 15,
                        color: _or,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ],
      );

  static pw.Widget _mentionPaiement(Vente v) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: v.paye
              ? const PdfColor.fromInt(0xFFE8F5E9)
              : const PdfColor.fromInt(0xFFFFF3E0),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Text(
          v.paye
              ? 'Facture réglée — merci de votre confiance.'
              : 'Facture non réglée à ce jour.',
          style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: v.paye
                  ? _vert
                  : const PdfColor.fromInt(0xFFE65100)),
        ),
      );

  static pw.Widget _pied(String vendeur) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(color: _clair, thickness: 2),
          pw.SizedBox(height: 6),
          if (vendeur.isNotEmpty)
            pw.Text('Établi par $vendeur',
                style: pw.TextStyle(fontSize: 9, color: _gris)),
          pw.Text(
              'Document émis le ${jour(DateTime.now())} par IDIAMA Agro',
              style: pw.TextStyle(fontSize: 9, color: _gris)),
        ],
      );

  static pw.Widget _ligneTotal(String libelle, String valeur,
          {bool gras = false, bool alerte = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(libelle,
                style: pw.TextStyle(
                    fontSize: gras ? 12 : 10,
                    fontWeight:
                        gras ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(valeur,
                style: pw.TextStyle(
                    fontSize: gras ? 13 : 10,
                    fontWeight:
                        gras ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: alerte
                        ? const PdfColor.fromInt(0xFFC62828)
                        : (gras ? _vert : PdfColors.black))),
          ],
        ),
      );

  static pw.Widget _th(String t, {bool droite = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: pw.Text(t,
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
                fontSize: 9.5,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _td(String t,
          {bool droite = false, bool gras = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: pw.Text(t,
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight:
                    gras ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  static pw.TextStyle _petit() => pw.TextStyle(
      fontSize: 8, color: _gris, fontWeight: pw.FontWeight.bold);

  static String _libelleType(String t) => switch (t) {
        'revendeur' => 'Revendeur',
        'particulier' => 'Particulier',
        'marche' => 'Marché',
        'restaurant' => 'Restaurant / Hôtel',
        _ => t,
      };
}
