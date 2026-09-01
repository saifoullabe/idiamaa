/// Les repères du métier — ce qui permet à l'application de dire
/// « c'est normal » ou « ça ne va pas » au lieu d'afficher un chiffre nu.
///
/// ⚠ Ce sont des valeurs INDICATIVES, issues des standards courants des
/// pondeuses commerciales en climat tropical. Elles servent de repère,
/// pas d'ordonnance. Le vétérinaire de la ferme reste seul juge :
/// le programme réel dépend de la souche, du fournisseur de vaccins et
/// de la pression sanitaire locale.

/// Le taux de ponte attendu d'un lot en bonne santé, selon son âge.
/// Avant 18 semaines une poule ne pond pas ; le pic est vers 25-30
/// semaines ; ensuite la courbe redescend lentement.
int ponteAttendue(int semaines) {
  if (semaines < 18) return 0;
  if (semaines < 19) return 10;
  if (semaines < 20) return 30;
  if (semaines < 21) return 55;
  if (semaines < 22) return 75;
  if (semaines < 23) return 85;
  if (semaines < 25) return 91;
  if (semaines < 31) return 94;
  if (semaines < 36) return 92;
  if (semaines < 41) return 90;
  if (semaines < 46) return 88;
  if (semaines < 51) return 85;
  if (semaines < 56) return 82;
  if (semaines < 61) return 79;
  if (semaines < 66) return 75;
  if (semaines < 71) return 71;
  if (semaines < 76) return 67;
  if (semaines < 81) return 63;
  return 58;
}

/// Dans quelle phase de sa vie se trouve le lot.
String phaseDuLot(int semaines) {
  if (semaines < 7) return 'Démarrage';
  if (semaines < 18) return 'Croissance';
  if (semaines < 25) return 'Entrée en ponte';
  if (semaines < 36) return 'Pic de ponte';
  if (semaines < 66) return 'Ponte établie';
  return 'Fin de cycle';
}

/// La mortalité cumulée acceptable à cet âge, en % de l'effectif de
/// départ. Environ 4 % la première année, un peu plus sur un cycle long.
double mortaliteAcceptable(int semaines) {
  if (semaines <= 0) return 0.5;
  // ~0,3 % la première semaine, puis ~0,06 % par semaine.
  return 0.3 + semaines * 0.06;
}

/// Une étape du calendrier vaccinal, repérée par l'âge du lot en jours.
class EtapeVaccin {
  final int jour;
  final String vaccin;
  final String voie;
  final String contre;

  const EtapeVaccin(this.jour, this.vaccin, this.voie, this.contre);

  int get semaine => (jour / 7).floor();
}

/// Programme indicatif pour un lot de pondeuses.
/// Les dates réelles se calculent en ajoutant ces jours à la date de
/// mise en place du bâtiment.
const List<EtapeVaccin> programmeVaccinal = [
  EtapeVaccin(1, 'Marek', 'Injection au couvoir',
      'la maladie de Marek (paralysie, tumeurs)'),
  EtapeVaccin(7, 'Newcastle HB1 + Bronchite', 'Goutte oculaire ou nasale',
      'la pseudo-peste aviaire et la bronchite infectieuse'),
  EtapeVaccin(14, 'Gumboro', 'Eau de boisson',
      'la bursite infectieuse, qui détruit les défenses du poussin'),
  EtapeVaccin(21, 'Gumboro (rappel)', 'Eau de boisson',
      'la bursite infectieuse'),
  EtapeVaccin(28, 'Newcastle Lasota', 'Eau de boisson',
      'la pseudo-peste aviaire'),
  EtapeVaccin(42, 'Variole aviaire', 'Transfixion de l’aile',
      'la variole aviaire (croûtes sur la crête et les barbillons)'),
  EtapeVaccin(56, 'Newcastle Lasota (rappel)', 'Eau de boisson',
      'la pseudo-peste aviaire'),
  EtapeVaccin(70, 'Coryza', 'Injection',
      'le coryza infectieux (écoulement nasal, gonflement de la face)'),
  EtapeVaccin(84, 'Newcastle + Bronchite', 'Eau de boisson',
      'la pseudo-peste et la bronchite'),
  EtapeVaccin(112, 'Coryza (rappel)', 'Injection', 'le coryza infectieux'),
  EtapeVaccin(126, 'Newcastle + Bronchite + EDS', 'Injection',
      'la chute de ponte (EDS 76) — juste avant l’entrée en ponte'),
  EtapeVaccin(210, 'Newcastle (rappel de ponte)', 'Eau de boisson',
      'la pseudo-peste, à refaire tous les 3 mois en ponte'),
  EtapeVaccin(300, 'Newcastle (rappel de ponte)', 'Eau de boisson',
      'la pseudo-peste'),
  EtapeVaccin(390, 'Newcastle (rappel de ponte)', 'Eau de boisson',
      'la pseudo-peste'),
  EtapeVaccin(480, 'Newcastle (rappel de ponte)', 'Eau de boisson',
      'la pseudo-peste'),
];

/// Les causes de mortalité qu'un fermier sait reconnaître sans vétérinaire.
const List<String> causesMortalite = [
  'inconnue',
  'maladie',
  'chaleur',
  'écrasement',
  'prédateur',
  'accident',
  'cannibalisme',
  'réforme',
];

String emojiCause(String cause) => switch (cause) {
      'maladie' => '🦠',
      'chaleur' => '🌡️',
      'écrasement' => '⚠️',
      'prédateur' => '🦊',
      'accident' => '💥',
      'cannibalisme' => '🩸',
      'réforme' => '📦',
      _ => '❓',
    };
