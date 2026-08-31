// Les objets de la ferme, tels qu'ils arrivent de la base.

int _int(dynamic v) => v == null ? 0 : (v is int ? v : num.parse('$v').round());
double _dbl(dynamic v) =>
    v == null ? 0 : (v is double ? v : num.parse('$v').toDouble());
String _txt(dynamic v) => v?.toString() ?? '';
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

class Ferme {
  final String id;
  final String nom;
  final String adresse;
  final String ville;
  final String statut;
  final String? gerantId;
  final int prixAlveole;
  final String notes;

  Ferme.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        nom = _txt(m['nom']),
        adresse = _txt(m['adresse']),
        ville = _txt(m['ville']),
        statut = _txt(m['statut']),
        gerantId = m['gerant_id'] as String?,
        prixAlveole = _int(m['prix_alveole']),
        notes = _txt(m['notes']);

  bool get suspendue => statut == 'Suspendue';
  bool get active => statut == 'Actif';
}

class Profil {
  final String id;
  final String login;
  final String nom;
  final String prenom;
  final String role;
  final String? fermeId;
  final String tel;
  final String tel2;
  final DateTime? dateNaissance;
  final String lieuNaissance;
  final String pere;
  final String mere;
  final String quartier;
  final String commune;
  final DateTime? dateEmbauche;
  final int salaire;
  final String notes;
  final String? photoUrl;
  final String? pieceUrl;
  final String? contratUrl;
  final bool suspendu;
  final DateTime? creeLe;

  Profil.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        login = _txt(m['login']),
        nom = _txt(m['nom']),
        prenom = _txt(m['prenom']),
        role = _txt(m['role']),
        fermeId = m['ferme_id'] as String?,
        tel = _txt(m['tel']),
        tel2 = _txt(m['tel2']),
        dateNaissance = _date(m['date_naissance']),
        lieuNaissance = _txt(m['lieu_naissance']),
        pere = _txt(m['pere']),
        mere = _txt(m['mere']),
        quartier = _txt(m['quartier']),
        commune = _txt(m['commune']),
        dateEmbauche = _date(m['date_embauche']),
        salaire = _int(m['salaire']),
        notes = _txt(m['notes']),
        photoUrl = m['photo_url'] as String?,
        pieceUrl = m['piece_url'] as String?,
        contratUrl = m['contrat_url'] as String?,
        suspendu = m['suspendu'] == true,
        creeLe = _date(m['cree_le']);

  String get nomComplet => '$nom $prenom'.trim();
  bool get estAdmin => role == 'admin';
  bool get estGerant => role == 'gerant';
  bool get estFermier => role == 'fermier';
}

class Batiment {
  final String id;
  final String fermeId;
  final String nom;
  final String type;
  final int nbPoules;
  final int prixAlveole;
  final int surface;
  final String etat;

  Batiment.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        nom = _txt(m['nom']),
        type = _txt(m['type']),
        nbPoules = _int(m['nb_poules']),
        prixAlveole = _int(m['prix_alveole']),
        surface = _int(m['surface']),
        etat = _txt(m['etat']);
}

/// Une saisie d'argent ou de production, avec son parcours de validation.
abstract class Saisie {
  String get id;
  String get fermeId;
  String get auteurId;
  String get statut;
  DateTime? get date;
  int get montant;
}

class Recette implements Saisie {
  @override
  final String id;
  @override
  final String fermeId;
  @override
  final String auteurId;
  final String roleAuteur;
  final String produit;
  final double quantite;
  final int prixUnitaire;
  @override
  final int montant;
  final String description;
  @override
  final DateTime? date;
  @override
  final String statut;
  final String motifRejet;

  Recette.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        auteurId = _txt(m['auteur_id']),
        roleAuteur = _txt(m['role_auteur']),
        produit = _txt(m['produit']),
        quantite = _dbl(m['quantite']),
        prixUnitaire = _int(m['prix_unitaire']),
        montant = _int(m['montant']),
        description = _txt(m['description']),
        date = _date(m['date']),
        statut = _txt(m['statut']),
        motifRejet = _txt(m['motif_rejet']);
}

class Depense implements Saisie {
  @override
  final String id;
  @override
  final String fermeId;
  @override
  final String auteurId;
  final String roleAuteur;
  final String categorie;
  final String article;
  final double quantite;
  final String unite;
  final int prixUnitaire;
  @override
  final int montant;
  final String description;
  @override
  final DateTime? date;
  @override
  final String statut;
  final String motifRejet;

  Depense.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        auteurId = _txt(m['auteur_id']),
        roleAuteur = _txt(m['role_auteur']),
        categorie = _txt(m['categorie']),
        article = _txt(m['article']),
        quantite = _dbl(m['quantite']),
        unite = _txt(m['unite']),
        prixUnitaire = _int(m['prix_unitaire']),
        montant = _int(m['montant']),
        description = _txt(m['description']),
        date = _date(m['date']),
        statut = _txt(m['statut']),
        motifRejet = _txt(m['motif_rejet']);
}

class Production implements Saisie {
  @override
  final String id;
  @override
  final String fermeId;
  final String batimentId;
  @override
  final String auteurId;
  final String roleAuteur;
  @override
  final DateTime? date;
  final int nbAlveoles;
  final int oeufs;
  final int valeur;
  @override
  final String statut;
  final String motifRejet;

  Production.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        batimentId = _txt(m['batiment_id']),
        auteurId = _txt(m['auteur_id']),
        roleAuteur = _txt(m['role_auteur']),
        date = _date(m['date']),
        nbAlveoles = _int(m['nb_alveoles']),
        oeufs = _int(m['oeufs']),
        valeur = _int(m['valeur']),
        statut = _txt(m['statut']),
        motifRejet = _txt(m['motif_rejet']);

  @override
  int get montant => valeur;
}

class Depot implements Saisie {
  @override
  final String id;
  @override
  final String fermeId;
  @override
  final String auteurId;
  final String roleAuteur;
  @override
  final int montant;
  @override
  final DateTime? date;
  final String reference;
  final String motif;
  final List<String> fichiers;
  @override
  final String statut;
  final String motifRejet;

  Depot.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        auteurId = _txt(m['auteur_id']),
        roleAuteur = _txt(m['role_auteur']),
        montant = _int(m['montant']),
        date = _date(m['date']),
        reference = _txt(m['reference']),
        motif = _txt(m['motif']),
        fichiers = ((m['fichiers'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        statut = _txt(m['statut']),
        motifRejet = _txt(m['motif_rejet']);
}

class Pointage {
  final String id;
  final String profilId;
  final String? fermeId;
  final DateTime debut;
  final DateTime? fin;
  final int? duree;
  final String statut;

  Pointage.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        profilId = _txt(m['profil_id']),
        fermeId = m['ferme_id'] as String?,
        debut = _date(m['debut']) ?? DateTime.now(),
        fin = _date(m['fin']),
        duree = m['duree'] == null ? null : _int(m['duree']),
        statut = _txt(m['statut']);

  bool get enCours => statut == 'en_cours';

  /// Durée réelle : celle enregistrée, ou celle qui court depuis l'arrivée.
  int get dureeSecondes =>
      duree ?? DateTime.now().difference(debut.toLocal()).inSeconds;
}

class Stock {
  final String id;
  final String fermeId;
  final String nom;
  final String categorie;
  final String unite;
  final double quantite;
  final double seuilMin;
  final String note;

  Stock.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        nom = _txt(m['nom']),
        categorie = _txt(m['categorie']),
        unite = _txt(m['unite']),
        quantite = _dbl(m['quantite']),
        seuilMin = _dbl(m['seuil_min']),
        note = _txt(m['note']);

  /// 0 → 100 : le remplissage affiché sur la jauge.
  int get niveau {
    final plafond = seuilMin > 0 ? seuilMin * 3 : 100;
    return (quantite / plafond * 100).clamp(0, 100).round();
  }

  bool get critique => niveau <= 30;
  bool get faible => niveau > 30 && niveau <= 60;
}

class MouvementStock {
  final String id;
  final String stockId;
  final String auteurId;
  final String type;
  final double quantite;
  final String unite;
  final String note;
  final DateTime? creeLe;

  MouvementStock.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        stockId = _txt(m['stock_id']),
        auteurId = _txt(m['auteur_id']),
        type = _txt(m['type']),
        quantite = _dbl(m['quantite']),
        unite = _txt(m['unite']),
        note = _txt(m['note']),
        creeLe = _date(m['cree_le']);

  bool get estEntree => type == 'entree';
}

class Signalement {
  final String id;
  final String fermeId;
  final String auteurId;
  final String? batimentId;
  final String titre;
  final String priorite;
  final String description;
  final DateTime? date;
  final String statut;
  final String reponse;

  Signalement.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        auteurId = _txt(m['auteur_id']),
        batimentId = m['batiment_id'] as String?,
        titre = _txt(m['titre']),
        priorite = _txt(m['priorite']),
        description = _txt(m['description']),
        date = _date(m['date']),
        statut = _txt(m['statut']),
        reponse = _txt(m['reponse']);

  bool get ouvert => statut == 'ouvert';
}

class Rapport {
  final String id;
  final String fermeId;
  final String auteurId;
  final String titre;
  final String activites;
  final String observations;
  final DateTime? date;

  Rapport.depuis(Map<String, dynamic> m)
      : id = _txt(m['id']),
        fermeId = _txt(m['ferme_id']),
        auteurId = _txt(m['auteur_id']),
        titre = _txt(m['titre']),
        activites = _txt(m['activites']),
        observations = _txt(m['observations']),
        date = _date(m['date']);
}
