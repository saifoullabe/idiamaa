/// Le pourcentage de ponte d'une période, tel que la base le calcule.
///
/// Rien n'est calculé ici : le téléphone ne connaît qu'une partie des
/// mortalités et des productions, et un pourcentage bâti là-dessus est
/// faux — il oublie les morts anciennes, diffère selon qu'on est gérant
/// ou administrateur, et dérive tout seul avec le temps. Voir
/// sql/17_idiama_ponte.sql.
class Ponte {
  /// TOUS les œufs validés de la période, même ceux d'un bâtiment dont
  /// personne n'a encore compté les poules.
  final int oeufs;

  /// Les œufs des seules journées dont on connaît le cheptel. C'est
  /// ceux-là qu'on divise : compter au numérateur des œufs dont le
  /// dénominateur est inconnu donnait « 120 % — excellent », en vert.
  final int oeufsMesures;

  /// La somme, sur ces mêmes journées, des poules vivantes CE jour-là.
  /// C'est par cela qu'on divise : sinon on compare les œufs d'octobre
  /// aux poules de novembre.
  final int poulesJours;

  /// Le nombre de journées-bâtiment retenues dans la mesure : trois
  /// bâtiments sur un jour en font trois. Sert à savoir si la période
  /// est assez remplie pour être comparée à une autre.
  final int jours;

  const Ponte(this.oeufs, this.oeufsMesures, this.poulesJours, this.jours);

  static const vide = Ponte(0, 0, 0, 0);

  Ponte.depuis(Map<String, dynamic> m)
      : oeufs = _entier(m['oeufs']),
        oeufsMesures = _entier(m['oeufs_mesures']),
        poulesJours = _entier(m['poules_jours']),
        jours = _entier(m['jours']);

  /// Le taux en pourcentage, ou null quand il n'y a rien à mesurer.
  double? get taux =>
      poulesJours > 0 ? oeufsMesures / poulesJours * 100 : null;

  /// Des œufs ramassés, mais aucune poule comptée pour les rapporter à
  /// quelque chose. L'écran doit le DIRE — « aucune saisie » serait un
  /// mensonge, et un pourcentage serait pire.
  bool get sansCheptelConnu => oeufs > 0 && poulesJours == 0;

  /// Au-delà, c'est une faute de saisie, pas un exploit : une poule ne
  /// pond pas plus d'un œuf par jour. On garde un peu de marge pour les
  /// arrondis et les ramassages rattrapés le lendemain.
  bool get invraisemblable => (taux ?? 0) > 105;

  static int _entier(dynamic v) =>
      v == null ? 0 : (v is int ? v : num.parse('$v').round());
}

/// Les huit périodes rendues par la base, en un seul appel.
class PonteComparee {
  final Ponte jour;
  final Ponte jourAvant;
  final Ponte semaine;
  final Ponte semaineAvant;
  final Ponte mois;
  final Ponte moisAvant;

  /// Les sept derniers jours glissants. « Cette semaine » un lundi matin
  /// ne contient qu'un jour : comparer cela au standard de l'âge du lot
  /// faisait crier à la chute de ponte chaque début de semaine.
  final Ponte septJours;
  final Ponte septJoursAvant;

  const PonteComparee({
    required this.jour,
    required this.jourAvant,
    required this.semaine,
    required this.semaineAvant,
    required this.mois,
    required this.moisAvant,
    required this.septJours,
    required this.septJoursAvant,
  });

  static const vide = PonteComparee(
    jour: Ponte.vide,
    jourAvant: Ponte.vide,
    semaine: Ponte.vide,
    semaineAvant: Ponte.vide,
    mois: Ponte.vide,
    moisAvant: Ponte.vide,
    septJours: Ponte.vide,
    septJoursAvant: Ponte.vide,
  );

  factory PonteComparee.depuis(List lignes) {
    final par = <String, Ponte>{};
    for (final l in lignes) {
      final m = l as Map<String, dynamic>;
      par['${m['periode']}'] = Ponte.depuis(m);
    }
    return PonteComparee.parPeriode(par);
  }

  factory PonteComparee.parPeriode(Map<String, Ponte> par) {
    Ponte p(String cle) => par[cle] ?? Ponte.vide;
    return PonteComparee(
      jour: p('jour'),
      jourAvant: p('jour_avant'),
      semaine: p('semaine'),
      semaineAvant: p('semaine_avant'),
      mois: p('mois'),
      moisAvant: p('mois_avant'),
      septJours: p('sept_jours'),
      septJoursAvant: p('sept_jours_avant'),
    );
  }

  /// Deux périodes ne se comparent que si elles sont de taille
  /// comparable.
  ///
  /// Sans cette règle, le lundi matin l'écran affichait « Cette semaine
  /// 45 % — 30 points de moins que la semaine passée », en rouge, parce
  /// qu'il mettait une matinée en face de sept jours complets. Le 1ᵉʳ du
  /// mois, c'était la ligne du mois. Le 1ᵉʳ janvier, les deux le même
  /// jour. Le troupeau, lui, n'avait rien changé.
  static bool comparables(Ponte maintenant, Ponte avant) {
    if (maintenant.jours == 0 || avant.jours == 0) return false;
    final petit = maintenant.jours < avant.jours ? maintenant.jours : avant.jours;
    final grand = maintenant.jours < avant.jours ? avant.jours : maintenant.jours;
    return petit * 2 >= grand;
  }

  /// L'écart en POINTS entre deux taux — pas en pourcentage : passer de
  /// 70 % à 77 %, c'est 7 points. Dire « +10 % » serait juste mais se
  /// confondrait avec le taux lui-même.
  static double? ecart(Ponte maintenant, Ponte avant) {
    if (!comparables(maintenant, avant)) return null;
    final a = maintenant.taux, b = avant.taux;
    if (a == null || b == null) return null;
    return a - b;
  }

  /// Comment dire l'écart, en français.
  static String direEcart(double? points) {
    if (points == null) return 'rien à comparer';
    if (points.abs() < 0.5) return 'comme avant';
    final signe = points > 0 ? '+' : '−';
    final valeur = points.abs().toStringAsFixed(1).replaceAll('.', ',');
    return '$signe$valeur point${points.abs() >= 2 ? 's' : ''}';
  }

  /// Pourquoi il n'y a rien à comparer — dit à la place de l'écart,
  /// parce qu'« une période trop courte » et « aucune saisie » ne
  /// demandent pas la même chose à l'éleveur.
  static String direPourquoiRien(Ponte maintenant, Ponte avant, String contre) {
    if (maintenant.sansCheptelConnu) return 'cheptel inconnu ces jours-là';
    if (maintenant.jours == 0 || avant.jours == 0) {
      return 'rien à comparer avec $contre';
    }
    return 'trop tôt pour comparer avec $contre';
  }
}

/// L'effectif d'un bâtiment, tel que la base le compte.
///
/// Le téléphone le déduisait d'une liste de morts plafonnée à 500
/// lignes : passé quelques mois, il croyait le cheptel plus grand qu'il
/// n'est, et pas du même montant selon qui regardait. Voir la vue
/// `batiments_vivants` dans sql/17_idiama_ponte.sql.
class Vivantes {
  /// Les poules présentes : le comptage du fermier, moins les morts
  /// déclarées depuis ce comptage.
  final int vivantes;

  /// Les morts déclarées depuis le comptage.
  final int morts;

  const Vivantes({required this.vivantes, required this.morts});
}
