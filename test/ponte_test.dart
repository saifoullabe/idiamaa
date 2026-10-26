// Le banc d'essai du pourcentage de ponte.
//
// Les chiffres eux-mêmes sont calculés par la base (sql/17) : ici on
// éprouve ce que le téléphone en fait — la division, l'écart en points,
// et surtout les cas où il n'y a RIEN à comparer. C'est là que l'écran
// mentait : il annonçait une chute de huit points sur un troupeau qui
// pondait exactement pareil, et une chute de trente points chaque lundi
// matin parce qu'il mettait une matinée en face de sept jours.
//
// Les clés des fixtures sont celles que rend la base, à la lettre :
// oeufs, oeufs_mesures, poules_jours, jours, periode.

import 'package:flutter_test/flutter_test.dart';
import 'package:idiama_agro/core/comparaison.dart';
import 'package:idiama_agro/core/format.dart';

void main() {
  group('Le taux d\'une période', () {
    test('se divise par les poules-jours, pas par un total', () {
      // 1 400 œufs pour 2 000 poules pendant 1 jour = 70 %.
      expect(const Ponte(1400, 1400, 2000, 1).taux, closeTo(70, 0.001));
      // Les mêmes 70 % sur sept jours : 9 800 œufs, 14 000 poules-jours.
      expect(const Ponte(9800, 9800, 14000, 7).taux, closeTo(70, 0.001));
    });

    test('vaut null quand il n\'y a aucune poule à mesurer', () {
      expect(Ponte.vide.taux, isNull);
      expect(const Ponte(500, 0, 0, 0).taux, isNull);
    });

    test('ne compte pas les œufs dont le cheptel est inconnu', () {
      // LE défaut : trois bâtiments, dont un sans comptage. Ses œufs
      // entraient au numérateur, zéro poule au dénominateur, et
      // l'écran affichait « 120 % — excellent », en vert.
      const p = Ponte(126000, 105000, 105000, 60);
      expect(p.oeufs, 126000); // le total reste juste
      expect(p.taux, closeTo(100, 0.001)); // et le taux ne gonfle pas
      expect(p.taux! <= 105, isTrue);
    });

    test('dit quand des œufs n\'ont aucune poule en face', () {
      const p = Ponte(2400, 0, 0, 0);
      expect(p.sansCheptelConnu, isTrue);
      expect(p.taux, isNull);
      // Et ce n'est pas la même chose que « rien de saisi ».
      expect(Ponte.vide.sansCheptelConnu, isFalse);
    });

    test('signale un chiffre impossible au lieu de le féliciter', () {
      // 200 alvéoles au lieu de 20 : 6 000 œufs pour 2 000 poules.
      const faute = Ponte(6000, 6000, 2000, 1);
      expect(faute.taux, closeTo(300, 0.001));
      expect(faute.invraisemblable, isTrue);
      // Une vraie bonne ponte, elle, n'est pas suspectée.
      expect(const Ponte(1900, 1900, 2000, 1).invraisemblable, isFalse);
    });

    test('ne sort jamais un NaN ni un infini', () {
      for (final p in [
        Ponte.vide,
        const Ponte(0, 0, 100, 1),
        const Ponte(100, 100, 1, 1),
      ]) {
        final t = p.taux;
        if (t != null) {
          expect(t.isFinite, isTrue, reason: 'taux non fini : $t');
        }
      }
    });

    test('lit ce que la base renvoie, même en texte', () {
      // PostgREST rend les bigint en nombre, mais une version future
      // pourrait les rendre en chaîne : on ne doit pas planter.
      final p = Ponte.depuis({
        'oeufs': '1400',
        'oeufs_mesures': '1400',
        'poules_jours': '2000',
        'jours': '1',
      });
      expect(p.oeufs, 1400);
      expect(p.poulesJours, 2000);
      expect(p.taux, closeTo(70, 0.001));
    });

    test('un champ absent vaut zéro, pas une exception', () {
      final p = Ponte.depuis({'oeufs': 300});
      expect(p.oeufs, 300);
      expect(p.poulesJours, 0);
      expect(p.taux, isNull);
      expect(p.sansCheptelConnu, isTrue);
    });
  });

  group('L\'écart entre deux périodes', () {
    test('se compte en POINTS, pas en pourcentage', () {
      const avant = Ponte(1400, 1400, 2000, 1); // 70 %
      const apres = Ponte(1540, 1540, 2000, 1); // 77 %
      expect(PonteComparee.ecart(apres, avant), closeTo(7, 0.001));
      expect(PonteComparee.direEcart(7), '+7,0 points');
    });

    test('n\'existe pas quand l\'une des deux périodes est vide', () {
      // Avant, une semaine sans saisie valait 0 % et l'écran annonçait
      // une chute de soixante-dix points.
      expect(
          PonteComparee.ecart(const Ponte(1400, 1400, 2000, 1), Ponte.vide),
          isNull);
      expect(
          PonteComparee.ecart(Ponte.vide, const Ponte(1400, 1400, 2000, 1)),
          isNull);
      expect(PonteComparee.ecart(Ponte.vide, Ponte.vide), isNull);
      expect(PonteComparee.direEcart(null), 'rien à comparer');
    });

    test('ne compare pas un lundi matin à sept jours complets', () {
      // Lundi, une seule journée mesurée, contre sept la semaine
      // d'avant. L'écran annonçait « −30,0 points », en rouge.
      const lundiMatin = Ponte(600, 600, 2000, 1); // 30 %
      const semainePassee = Ponte(9800, 9800, 14000, 7); // 70 %
      expect(PonteComparee.comparables(lundiMatin, semainePassee), isFalse);
      expect(PonteComparee.ecart(lundiMatin, semainePassee), isNull);
      expect(
          PonteComparee.direPourquoiRien(
              lundiMatin, semainePassee, 'la semaine passée'),
          'trop tôt pour comparer avec la semaine passée');
    });

    test('compare dès que les deux périodes sont de taille voisine', () {
      // Quatre jours contre sept : c'est assez pour être honnête.
      const quatreJours = Ponte(5600, 5600, 8000, 4); // 70 %
      const septJours = Ponte(9800, 9800, 14000, 7); // 70 %
      expect(PonteComparee.comparables(quatreJours, septJours), isTrue);
      expect(PonteComparee.ecart(quatreJours, septJours), closeTo(0, 0.001));
      expect(PonteComparee.direEcart(0), 'comme avant');
    });

    test('un troupeau qui pond pareil ne paraît pas en baisse', () {
      // Le mois passé : 2 000 poules, 30 jours, 70 %.
      const moisPasse = Ponte(42000, 42000, 60000, 30);
      // Ce mois : 300 mortes, donc 1 700 poules, toujours 70 %.
      const ceMois = Ponte(35700, 35700, 51000, 30);
      final points = PonteComparee.ecart(ceMois, moisPasse);
      expect(points, isNotNull);
      expect(points!.abs() < 0.5, isTrue,
          reason: 'écart annoncé de $points points sur une ponte identique');
      expect(PonteComparee.direEcart(points), 'comme avant');
    });

    test('se dit en français, virgule comprise', () {
      expect(PonteComparee.direEcart(0), 'comme avant');
      expect(PonteComparee.direEcart(0.2), 'comme avant');
      expect(PonteComparee.direEcart(-0.4), 'comme avant');
      expect(PonteComparee.direEcart(1), '+1,0 point');
      expect(PonteComparee.direEcart(2), '+2,0 points');
      expect(PonteComparee.direEcart(-3.5), '−3,5 points');
      // Le signe moins doit être le vrai signe moins, pas un trait
      // d'union : il s'aligne avec les chiffres.
      expect(PonteComparee.direEcart(-3.5).startsWith('−'), isTrue);
      // Et jamais de point décimal anglais.
      expect(PonteComparee.direEcart(7).contains('.'), isFalse);
    });

    test('la raison du « rien à comparer » est la bonne', () {
      expect(
          PonteComparee.direPourquoiRien(
              const Ponte(2400, 0, 0, 0), Ponte.vide, 'hier'),
          'cheptel inconnu ces jours-là');
      expect(PonteComparee.direPourquoiRien(Ponte.vide, Ponte.vide, 'hier'),
          'rien à comparer avec hier');
    });
  });

  group('Le pourcentage écrit à l\'écran', () {
    test('porte la virgule française et le signe pour cent', () {
      expect(pourcent(60), '60,0 %');
      expect(pourcent(7.25), '7,3 %');
      expect(pourcent(null), '—');
      expect(pourcent(100, decimales: 0), '100 %');
    });
  });

  group('Les périodes renvoyées par la base', () {
    test('se rangent par leur nom, et les absentes restent vides', () {
      final c = PonteComparee.depuis([
        {
          'periode': 'jour',
          'oeufs': 1400,
          'oeufs_mesures': 1400,
          'poules_jours': 2000,
          'jours': 1
        },
        {
          'periode': 'jour_avant',
          'oeufs': 1300,
          'oeufs_mesures': 1300,
          'poules_jours': 2000,
          'jours': 1
        },
        {
          'periode': 'sept_jours',
          'oeufs': 9800,
          'oeufs_mesures': 9800,
          'poules_jours': 14000,
          'jours': 7
        },
      ]);
      expect(c.jour.taux, closeTo(70, 0.001));
      expect(c.jourAvant.taux, closeTo(65, 0.001));
      expect(c.septJours.taux, closeTo(70, 0.001));
      expect(PonteComparee.ecart(c.jour, c.jourAvant), closeTo(5, 0.001));
      // Rien pour la semaine ni le mois : pas zéro, RIEN.
      expect(c.semaine.taux, isNull);
      expect(c.mois.taux, isNull);
      expect(c.moisAvant.taux, isNull);
      expect(PonteComparee.ecart(c.mois, c.moisAvant), isNull);
    });

    test('une réponse vide ne plante pas', () {
      final c = PonteComparee.depuis([]);
      expect(c.jour.taux, isNull);
      expect(c.septJours.taux, isNull);
    });

    test('une période inconnue de l\'application est ignorée', () {
      final c = PonteComparee.depuis([
        {
          'periode': 'trimestre',
          'oeufs': 10,
          'oeufs_mesures': 10,
          'poules_jours': 20,
          'jours': 1
        },
        {
          'periode': 'jour',
          'oeufs': 1400,
          'oeufs_mesures': 1400,
          'poules_jours': 2000,
          'jours': 1
        },
      ]);
      expect(c.jour.taux, closeTo(70, 0.001));
    });
  });

  group('L\'effectif vivant tel que la base le compte', () {
    test('garde les deux nombres séparés', () {
      const v = Vivantes(vivantes: 1700, morts: 300);
      expect(v.vivantes, 1700);
      expect(v.morts, 300);
    });
  });
}
