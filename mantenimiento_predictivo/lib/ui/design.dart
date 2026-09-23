import 'package:flutter/material.dart';

const ink = Color(0xFF172B35);
const muted = Color(0xFF6B7D86);
const accent = Color(0xFF087F74);
const canvas = Color(0xFFF3F6F7);
const line = Color(0xFFE1E8EB);

ThemeData predictaTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: accent, surface: Colors.white),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.4, color: ink),
    headlineMedium: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -.8, color: ink),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
  ),
  appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
  cardTheme: CardThemeData(elevation: 0, margin: EdgeInsets.zero, color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: line))),
  inputDecorationTheme: InputDecorationTheme(
    filled: true, fillColor: const Color(0xFFF8FAFB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accent, width: 1.5)),
  ),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
  snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
  dividerColor: line,
);

class Brand extends StatelessWidget {
  final bool light;
  const Brand({super.key, this.light = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(11)),
      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 25)),
    const SizedBox(width: 12),
    Text('predicta', style: TextStyle(color: light ? Colors.white : ink, fontSize: 25, fontWeight: FontWeight.w700, letterSpacing: -1)),
  ]);
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(this.text, {super.key, this.color = accent});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 7), Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onRetry;
  const EmptyState({super.key, required this.title, required this.subtitle, this.icon = Icons.sensors_off_rounded, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 44, color: muted), const SizedBox(height: 18),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
      if (onRetry != null) Padding(padding: const EdgeInsets.only(top: 20), child: OutlinedButton.icon(
        onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar'))),
    ],
  )));
}
