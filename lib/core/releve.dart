import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'format.dart';
import 'polices.dart';

/// Une ligne du relevé : un libellé, une valeur, et parfois un détail.
class LigneReleve {
  final String libelle;
  final String valeur;
  final String? detail;
  final bool gras;

  const LigneReleve(this.libelle, this.valeur, {this.detail, this.gras = false});
}

/// Un bloc du relevé : un titre et ses lignes.
class BlocReleve {
  final String titre;
  final List<LigneReleve> lignes;

  const BlocReleve(this.titre, this.lignes);
}

/// Le relevé de compte, en PDF.
///
/// Il est fabriqué sur le téléphone, à partir de ce qui est affiché à
/// l'écran : ce que la personne lit sur le papier est exactement ce
/// qu'elle voit dans l'application, au moment où elle l'édite.
class Releve {
  static const _vert = PdfColor.fromInt(0xFF1B5E20);
  static const _or = PdfColor.fromInt(0xFFF9A825);
  static const _gris = PdfColor.fromInt(0xFF607D8B);
  static const _clair = PdfColor.fromInt(0xFFF1F4EF);

  static Future<void> editer({
    required String titre,
    required String periode,
    required String portee,
    required String editePar,
    required List<BlocReleve> blocs,
    required List<LigneReleve> enTete,
  }) async {
    final doc = pw.Document(theme: await Polices.theme());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 52),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Page ${ctx.pageNumber} sur ${ctx.pagesCount}'
            '   ·   Édité le ${jourLong(DateTime.now())} à ${heure(DateTime.now())}'
            '   ·   $editePar',
            style: const pw.TextStyle(fontSize: 8, color: _gris),
          ),
        ),
        build: (ctx) => [
          _entete(titre, periode, portee),
          pw.SizedBox(height: 18),
          if (enTete.isNotEmpty) ...[
            _chiffresClefs(enTete),
            pw.SizedBox(height: 20),
          ],
          for (final b in blocs) ...[
            _bloc(b),
            pw.SizedBox(height: 16),
          ],
          pw.SizedBox(height: 8),
          _mention(),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'releve-${periode.replaceAll(' ', '-').toLowerCase()}.pdf',
    );
  }

  static pw.Widget _entete(String titre, String periode, String portee) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('IDIAMA AGRO',
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _vert,
                    letterSpacing: 1)),
            pw.SizedBox(height: 2),
            pw.Text('Gestion des fermes avicoles',
                style: const pw.TextStyle(fontSize: 9, color: _gris)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(titre,
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const pw.BoxDecoration(color: _clair),
              child: pw.Text(periode,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 4),
            pw.Text(portee, style: const pw.TextStyle(fontSize: 9, color: _gris)),
          ]),
        ],
      );

  static pw.Widget _chiffresClefs(List<LigneReleve> lignes) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _or, width: 1.2),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            for (final l in lignes)
              pw.Expanded(
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(l.libelle.toUpperCase(),
                          style: const pw.TextStyle(fontSize: 7, color: _gris)),
                      pw.SizedBox(height: 3),
                      pw.Text(l.valeur,
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: _vert)),
                      if (l.detail != null)
                        pw.Text(l.detail!,
                            style:
                                const pw.TextStyle(fontSize: 7, color: _gris)),
                    ]),
              ),
          ],
        ),
      );

  /// Un tableau, et non une colonne : la première ligne porte
  /// `repeat: true`, donc le titre du bloc est redessiné en haut de
  /// chaque page. Sans cela, un relevé annuel pouvait couper un bloc
  /// juste après son bandeau — et la page suivante montrait une colonne
  /// de montants sans qu'on sache s'il s'agit d'argent entré ou sorti.
  static pw.Widget _bloc(BlocReleve b) => pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(5),
          1: pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _vert),
            children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Text(b.titre.toUpperCase(),
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.8)),
              ),
              pw.SizedBox(),
            ],
          ),
          if (b.lignes.isEmpty)
            pw.TableRow(children: [
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: pw.Text('Rien sur cette période',
                    style: pw.TextStyle(
                        fontSize: 9,
                        color: _gris,
                        fontStyle: pw.FontStyle.italic)),
              ),
              pw.SizedBox(),
            ])
          else
            for (var i = 0; i < b.lignes.length; i++)
              _ligne(b.lignes[i], i.isEven),
        ],
      );

  static pw.TableRow _ligne(LigneReleve l, bool pair) => pw.TableRow(
        decoration: pw.BoxDecoration(color: pair ? PdfColors.white : _clair),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(l.libelle,
                      style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: l.gras
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal)),
                  if (l.detail != null)
                    pw.Text(l.detail!,
                        style: const pw.TextStyle(fontSize: 7.5, color: _gris)),
                ]),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(l.valeur,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight:
                        l.gras ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
        ],
      );

  static pw.Widget _mention() => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: const pw.BoxDecoration(color: _clair),
        child: pw.Text(
          'Ce relevé reprend ce qui était enregistré au moment de son édition. '
          'Les montants « en attente » ne sont pas encore validés : ils ne '
          'comptent dans aucun total tant qu\'ils ne le sont pas.',
          style: const pw.TextStyle(fontSize: 7.5, color: _gris),
        ),
      );
}
