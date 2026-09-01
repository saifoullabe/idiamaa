import 'package:geolocator/geolocator.dart';

/// Ce que l'application a obtenu — ou pas — quand elle a demandé la
/// position. On distingue les cas, parce que le message à afficher au
/// fermier n'est pas le même s'il a refusé ou si le GPS est éteint.
enum EtatPosition {
  ok,
  serviceEteint,
  refusee,
  refuseeDefinitivement,
  simulee,
  erreur,
}

class Position2 {
  final EtatPosition etat;
  final double? latitude;
  final double? longitude;
  final double? precisionMetres;

  const Position2(this.etat,
      {this.latitude, this.longitude, this.precisionMetres});

  bool get utilisable => etat == EtatPosition.ok;

  String get explication => switch (etat) {
        EtatPosition.ok => 'Position obtenue',
        EtatPosition.serviceEteint =>
          'La localisation du téléphone est éteinte. Activez-la dans les '
              'réglages, puis réessayez.',
        EtatPosition.refusee =>
          'L’application a besoin de votre position pour vérifier que vous '
              'êtes bien à la ferme. Autorisez-la et réessayez.',
        EtatPosition.refuseeDefinitivement =>
          'La localisation a été refusée définitivement. Ouvrez les réglages '
              'du téléphone, cherchez IDIAMA Agro, et autorisez la position.',
        EtatPosition.simulee =>
          'Position simulée détectée. Le pointage n’est possible qu’avec la '
              'vraie position du téléphone.',
        EtatPosition.erreur =>
          'Impossible d’obtenir la position. Sortez à l’air libre et '
              'réessayez : sous une tôle, le GPS ne capte pas.',
      };
}

class Localisation {
  /// Demande la position réelle du téléphone, en refusant tout ce qui
  /// ressemble à une position fabriquée.
  static Future<Position2> position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const Position2(EtatPosition.serviceEteint);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const Position2(EtatPosition.refuseeDefinitivement);
      }
      if (permission == LocationPermission.denied) {
        return const Position2(EtatPosition.refusee);
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      // Android sait dire qu'une position vient d'une fausse application
      // de GPS. On refuse : sinon la vérification ne vaut rien.
      if (p.isMocked) return const Position2(EtatPosition.simulee);

      return Position2(EtatPosition.ok,
          latitude: p.latitude,
          longitude: p.longitude,
          precisionMetres: p.accuracy);
    } catch (_) {
      return const Position2(EtatPosition.erreur);
    }
  }

  /// La distance entre deux points, en mètres. Même formule que celle
  /// posée dans la base, pour que l'écran et le serveur soient d'accord.
  static double distance(
          double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
}
