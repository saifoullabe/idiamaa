import 'package:intl/intl.dart';

final NumberFormat _nombre = NumberFormat.decimalPattern('fr_FR');
final DateFormat _jourCourt = DateFormat('dd/MM/yyyy', 'fr_FR');
final DateFormat _jourLong = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
final DateFormat _jourMois = DateFormat('d MMM', 'fr_FR');
final DateFormat _moisAnnee = DateFormat('MMMM yyyy', 'fr_FR');
final DateFormat _heure = DateFormat('HH:mm', 'fr_FR');
final DateFormat _heureSec = DateFormat('HH:mm:ss', 'fr_FR');

/// 1234567 → « 1 234 567 »
String nb(num? v) => _nombre.format(v ?? 0).replaceAll(' ', ' ');

/// 1234567 → « 1 234 567 GNF »
String gnf(num? v) => '${nb(v)} GNF';

/// 1234567 → « 1,2 M » — pour les grands chiffres des tableaux de bord.
String gnfCourt(num? v) {
  final x = (v ?? 0).abs();
  final signe = (v ?? 0) < 0 ? '-' : '';
  if (x >= 1000000000) {
    return '$signe${(x / 1000000000).toStringAsFixed(1).replaceAll('.', ',')} Md';
  }
  if (x >= 1000000) {
    return '$signe${(x / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M';
  }
  if (x >= 10000) {
    return '$signe${(x / 1000).toStringAsFixed(0)} k';
  }
  return nb(v);
}

String jour(DateTime? d) => d == null ? '—' : _jourCourt.format(d);
String jourLong(DateTime? d) => d == null ? '—' : _jourLong.format(d);
String jourMois(DateTime? d) => d == null ? '—' : _jourMois.format(d);
String moisAnnee(DateTime? d) => d == null ? '—' : _moisAnnee.format(d);
String heure(DateTime? d) => d == null ? '—' : _heure.format(d.toLocal());
String heureSec(DateTime? d) => d == null ? '—' : _heureSec.format(d.toLocal());

/// Date au format que comprend la base : 2026-08-31
String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime aujourdhui() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// 37528 secondes → « 10h 25min »
String duree(int? secondes) {
  if (secondes == null) return '—';
  final h = secondes ~/ 3600;
  final m = (secondes % 3600) ~/ 60;
  if (h == 0) return '${m}min';
  return '${h}h ${m.toString().padLeft(2, '0')}min';
}

/// 37528 secondes → « 10:25:28 » — pour le chronomètre du pointage.
String chrono(int secondes) {
  final h = secondes ~/ 3600;
  final m = (secondes % 3600) ~/ 60;
  final s = secondes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// « il y a 3 jours »
String depuis(DateTime? d) {
  if (d == null) return '—';
  final ecart = DateTime.now().difference(d);
  if (ecart.inMinutes < 1) return 'à l’instant';
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays == 1) return 'hier';
  if (ecart.inDays < 30) return 'il y a ${ecart.inDays} jours';
  return jour(d);
}

String initiales(String nom) {
  final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
  if (mots.isEmpty) return '?';
  if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
  return (mots.first.substring(0, 1) + mots.elementAt(1).substring(0, 1))
      .toUpperCase();
}
