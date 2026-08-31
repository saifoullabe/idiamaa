import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// La courbe des œufs ramassés sur les derniers jours.
class CourbeProduction extends StatelessWidget {
  final List<({DateTime jour, int oeufs, int valeur})> serie;

  const CourbeProduction(this.serie, {super.key});

  @override
  Widget build(BuildContext context) {
    final maximum = serie.fold<int>(0, (m, e) => e.oeufs > m ? e.oeufs : m);
    if (maximum == 0) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text('Aucune production sur la période',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maximum * 1.25,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maximum / 3,
            getDrawingHorizontalLine: (_) => FlLine(
                color: Theme.of(context).dividerColor, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: maximum / 2,
                getTitlesWidget: (v, meta) => Text(gnfCourt(v),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= serie.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(jourMois(serie[i].jour),
                        style: Theme.of(context).textTheme.labelSmall),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (points) => points
                  .map((p) => LineTooltipItem(
                        '${nb(serie[p.x.round()].oeufs)} œufs',
                        const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < serie.length; i++)
                  FlSpot(i.toDouble(), serie[i].oeufs.toDouble()),
              ],
              isCurved: true,
              curveSmoothness: 0.32,
              barWidth: 3,
              color: Palette.vertMoyen,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 3.6,
                  color: Colors.white,
                  strokeWidth: 2.4,
                  strokeColor: Palette.vertMoyen,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Palette.vertClair.withValues(alpha: 0.32),
                    Palette.vertClair.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les barres recettes / dépenses mois par mois.
class BarresMensuelles extends StatelessWidget {
  final List<({DateTime mois, int recettes, int depenses})> serie;

  const BarresMensuelles(this.serie, {super.key});

  @override
  Widget build(BuildContext context) {
    final maximum = serie.fold<int>(
        0,
        (m, e) => [m, e.recettes, e.depenses]
            .reduce((a, b) => a > b ? a : b));
    if (maximum == 0) {
      return SizedBox(
        height: 130,
        child: Center(
          child: Text('Aucun mouvement sur la période',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    return Column(children: [
      SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            maxY: maximum * 1.2,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maximum / 3,
              getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).dividerColor, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: maximum / 2,
                  getTitlesWidget: (v, meta) => Text(gnfCourt(v),
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if (i < 0 || i >= serie.length) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          moisAnnee(serie[i].mois).split(' ').first.substring(
                              0,
                              moisAnnee(serie[i].mois).split(' ').first.length >
                                      4
                                  ? 4
                                  : moisAnnee(serie[i].mois)
                                      .split(' ')
                                      .first
                                      .length),
                          style: Theme.of(context).textTheme.labelSmall),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (groupe, _, barre, index) => BarTooltipItem(
                  '${index == 0 ? 'Recettes' : 'Dépenses'}\n${gnf(barre.toY)}',
                  const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < serie.length; i++)
                BarChartGroupData(x: i, barsSpace: 4, barRods: [
                  BarChartRodData(
                    toY: serie[i].recettes.toDouble(),
                    color: Palette.vertMoyen,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                  BarChartRodData(
                    toY: serie[i].depenses.toDouble(),
                    color: Palette.rouge,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Legende(couleur: Palette.vertMoyen, texte: 'Recettes'),
        SizedBox(width: 20),
        _Legende(couleur: Palette.rouge, texte: 'Dépenses'),
      ]),
    ]);
  }
}

class _Legende extends StatelessWidget {
  final Color couleur;
  final String texte;
  const _Legende({required this.couleur, required this.texte});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
                color: couleur, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(texte, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// La répartition des dépenses par catégorie, en anneau.
class AnneauCategories extends StatelessWidget {
  final List<({String libelle, int montant, Color couleur})> parts;

  const AnneauCategories(this.parts, {super.key});

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (s, p) => s + p.montant);
    if (total == 0) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('Aucune dépense validée',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    final visibles = parts.where((p) => p.montant > 0).toList();

    return Row(children: [
      SizedBox(
        width: 140,
        height: 140,
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 40,
            sections: [
              for (final p in visibles)
                PieChartSectionData(
                  value: p.montant.toDouble(),
                  color: p.couleur,
                  radius: 26,
                  showTitle: false,
                ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in visibles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: p.couleur,
                        borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.libelle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Text('${(p.montant / total * 100).round()} %',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: p.couleur)),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }
}
