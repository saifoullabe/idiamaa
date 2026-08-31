import 'package:flutter/material.dart';

/// Les cinq catégories de dépenses de la ferme, telles que définies
/// dans le cahier des charges IDIAMA.
class CategorieDepense {
  final String cle;
  final String libelle;
  final String emoji;
  final Color couleur;
  final Color fond;
  final List<String> articles;

  const CategorieDepense({
    required this.cle,
    required this.libelle,
    required this.emoji,
    required this.couleur,
    required this.fond,
    required this.articles,
  });

  String get titre => '$emoji  $libelle';
}

const List<CategorieDepense> categoriesDepense = [
  CategorieDepense(
    cle: 'aliment',
    libelle: 'Alimentation',
    emoji: '🌽',
    couleur: Color(0xFF1B5E20),
    fond: Color(0xFFE8F5E9),
    articles: [
      'Aliment pondeuse',
      'Aliment poussin',
      'Son de maïs',
      'Maïs grain',
      'Soja',
      'Compléments minéraux',
      'Sel',
      'Prémix vitaminé',
    ],
  ),
  CategorieDepense(
    cle: 'medicament',
    libelle: 'Médicaments',
    emoji: '💊',
    couleur: Color(0xFF1565C0),
    fond: Color(0xFFE3F2FD),
    articles: [
      'Vaccin Newcastle',
      'Vaccin Gumboro',
      'Vaccin Bronchite',
      'Antibiotique',
      'Vitamines',
      'Vermifuge',
      'Désinfectant',
    ],
  ),
  CategorieDepense(
    cle: 'batiment',
    libelle: 'Construction',
    emoji: '🏗️',
    couleur: Color(0xFFBF360C),
    fond: Color(0xFFFFF3E0),
    articles: [
      'Ciment',
      'Fer',
      'Tôle',
      'Brique',
      'Grillage',
      'Pointe',
      'Bois',
      'Peinture',
      'Sable',
      'Gravier',
      'Tuyau PVC',
    ],
  ),
  CategorieDepense(
    cle: 'salaire',
    libelle: 'Salaires',
    emoji: '👷',
    couleur: Color(0xFF6A1B9A),
    fond: Color(0xFFF3E5F5),
    articles: [
      'Ouvrier permanent',
      'Main d’œuvre journalière',
      'Gardien',
      'Technicien vétérinaire',
      'Responsable ferme',
      'Chauffeur',
    ],
  ),
  CategorieDepense(
    cle: 'autre',
    libelle: 'Autres dépenses',
    emoji: '📎',
    couleur: Color(0xFF37474F),
    fond: Color(0xFFECEFF1),
    articles: [
      'Transport',
      'Carburant',
      'Eau',
      'Électricité',
      'Téléphone',
      'Matériel divers',
    ],
  ),
];

CategorieDepense categorie(String cle) => categoriesDepense.firstWhere(
      (c) => c.cle == cle,
      orElse: () => categoriesDepense.last,
    );

const List<String> produitsRecette = [
  'Œufs (unité)',
  'Œufs (plateau 30)',
  'Poule réformée',
  'Fumier',
  'Autre',
];

const List<String> typesBatiment = [
  'Pondeuses',
  'Poussins',
  'Quarantaine',
  'Stock',
];

const List<String> etatsBatiment = ['Bon', 'Correct', 'Mauvais'];

const List<String> statutsFerme = ['Actif', 'Maintenance', 'Suspendue', 'Fermé'];

const List<String> unitesStock = ['kg', 'sac', 'lot', 'litre', 'u.', 'plateau'];

/// Nombre d'œufs contenus dans une alvéole.
const int oeufsParAlveole = 30;

/// Prix par défaut d'une alvéole, en francs guinéens.
const int prixAlveoleDefaut = 22000;

// ── Statuts de validation ─────────────────────────────────────────────
class Statut {
  static const attenteGerant = 'attente_gerant';
  static const attenteAdmin = 'attente_admin';
  static const valide = 'valide';
  static const rejete = 'rejete';

  static bool enAttente(String s) => s.startsWith('attente');

  static String libelle(String s) => switch (s) {
        valide => 'Validé',
        rejete => 'Rejeté',
        attenteGerant => 'Attente gérant',
        attenteAdmin => 'Attente admin',
        _ => s,
      };

  static IconData icone(String s) => switch (s) {
        valide => Icons.check_circle_rounded,
        rejete => Icons.cancel_rounded,
        _ => Icons.hourglass_top_rounded,
      };

  static Color couleur(String s) => switch (s) {
        valide => const Color(0xFF2E7D32),
        rejete => const Color(0xFFC62828),
        _ => const Color(0xFFEF6C00),
      };

  /// Statut que reçoit une saisie selon qui la crée.
  static String aLaCreation(String role) => switch (role) {
        'fermier' => attenteGerant,
        'gerant' => attenteAdmin,
        _ => valide,
      };
}

class Role {
  static const admin = 'admin';
  static const gerant = 'gerant';
  static const fermier = 'fermier';

  static String libelle(String r) => switch (r) {
        admin => 'Administrateur',
        gerant => 'Gérant de ferme',
        _ => 'Fermier',
      };

  static String emoji(String r) => switch (r) {
        admin => '👑',
        gerant => '🏚️',
        _ => '👨‍🌾',
      };
}

const List<String> prioritesSignalement = ['urgent', 'normal', 'info'];

Color couleurPriorite(String p) => switch (p) {
      'urgent' => const Color(0xFFC62828),
      'normal' => const Color(0xFFEF6C00),
      _ => const Color(0xFF0277BD),
    };
