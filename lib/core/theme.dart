import 'package:flutter/material.dart';

import '../data/models.dart';

const kBg = Color(0xFFF4F6FA);
const kLine = Color(0xFFE3E8F0);
const kIn = Color(0xFF16834F);
const kOut = Color(0xFFD9480F);

Color typeColor(VType t) => t.isIn ? kIn : kOut;
IconData typeIcon(VType t) => t.isIn ? Icons.south_west_rounded : Icons.north_east_rounded;

ThemeData buildTheme() {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF1E5AA8), surface: Colors.white);
  final radius = BorderRadius.circular(12);
  OutlineInputBorder border([Color c = kLine]) => OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c));
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1B2433)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kLine)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(cs.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: radius))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: radius))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    dividerTheme: const DividerThemeData(color: kLine, space: 1, thickness: 1),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: Colors.white),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, height: 68),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: const BorderSide(color: kLine)),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}
