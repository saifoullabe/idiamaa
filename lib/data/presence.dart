import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Le suivi de présence pendant qu'un fermier est en ligne.
///
/// Tant que le pointage est ouvert, le téléphone envoie sa position —
/// écran éteint, application en arrière-plan. Android l'autorise à
/// condition d'afficher une notification permanente : c'est la
/// contrepartie, et elle est honnête, la personne voit qu'elle est suivie.
///
/// Si l'application est tuée de force, plus rien ne part : c'est la base
/// qui prend le relais et ferme le pointage après 30 minutes de silence.
class Presence {
  static StreamSubscription<Position>? _flux;
  static Timer? _battement;

  /// Ce que la base a répondu au dernier envoi.
  static final ValueNotifier<String?> dernierMessage =
      ValueNotifier<String?>(null);
  static final ValueNotifier<int?> derniereDistance =
      ValueNotifier<int?>(null);

  static bool get actif => _flux != null;

  /// Demande l'autorisation « tout le temps ». Sans elle, Android coupe
  /// la position dès que l'écran s'éteint.
  static Future<bool> autorisationArrierePlan() async {
    if (kIsWeb) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.always) return true;
    if (p == LocationPermission.whileInUse) {
      // Sur Android, redemander depuis cet état ouvre le réglage
      // « Autoriser tout le temps ».
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always;
  }

  static Future<void> demarrer({
    required void Function(String message) surSortie,
  }) async {
    if (kIsWeb || _flux != null) return;

    final reglages = AndroidSettings(
      accuracy: LocationAccuracy.high,
      // On ne réagit qu'aux déplacements réels : inutile de bombarder
      // le serveur quand la personne travaille au même endroit.
      distanceFilter: 30,
      intervalDuration: const Duration(minutes: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'IDIAMA Agro — pointage en cours',
        notificationText:
            'Votre présence à la ferme est vérifiée tant que vous êtes en ligne.',
        notificationChannelName: 'Présence à la ferme',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _flux = Geolocator.getPositionStream(locationSettings: reglages)
        .listen((p) => _envoyer(p, surSortie), onError: (_) {});

    // Filet de sécurité : même immobile, on donne signe de vie toutes
    // les 10 minutes, sinon la base croirait le téléphone muet.
    _battement = Timer.periodic(const Duration(minutes: 10), (_) async {
      try {
        final p = await Geolocator.getLastKnownPosition();
        if (p != null) await _envoyer(p, surSortie);
      } catch (_) {}
    });
  }

  static Future<void> _envoyer(
      Position p, void Function(String) surSortie) async {
    // Une position fabriquée n'a aucune valeur de preuve : on l'ignore,
    // et le silence qui s'ensuit fermera le pointage.
    if (p.isMocked) return;
    try {
      final r = await Supabase.instance.client.rpc(
        'confirmer_presence',
        params: {'p_latitude': p.latitude, 'p_longitude': p.longitude},
      );
      if (r is! List || r.isEmpty) return;
      final ligne = r.first as Map<String, dynamic>;
      final enLigne = ligne['en_ligne'] == true;
      final motif = '${ligne['motif'] ?? ''}';
      derniereDistance.value = ligne['distance'] == null
          ? null
          : int.tryParse('${ligne['distance']}');
      dernierMessage.value = motif;
      if (!enLigne) {
        await arreter();
        surSortie(motif);
      }
    } catch (_) {
      // Réseau coupé : on ne fait rien. Si le silence dure, la base
      // fermera le pointage d'elle-même.
    }
  }

  static Future<void> arreter() async {
    await _flux?.cancel();
    _flux = null;
    _battement?.cancel();
    _battement = null;
    derniereDistance.value = null;
    dernierMessage.value = null;
  }
}
