import 'package:flutter/material.dart';
import 'pages/room_list_page.dart';

void main() => runApp(const StudyMateApp());

class StudyMateApp extends StatelessWidget {
  const StudyMateApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI 스터디메이트',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      scaffoldBackgroundColor: const Color(0xFFF4F5F7),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFC),
        surface: Colors.white,
        primary: const Color(0xFF7C5CFC), onPrimary: Colors.white),
      dividerTheme: const DividerThemeData(color: Color(0xFFE9EAEE)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF191A1C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: Color(0xFFE9EAEE))),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF191A1C))),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE9EAEE)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF7C5CFC), foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16), textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      chipTheme: ChipThemeData(backgroundColor: Colors.white, selectedColor: const Color(0xFFF1EDFF),
        side: const BorderSide(color: Color(0xFFE1E3E8)), labelStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, color: Color(0xFF3A3D44)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      listTileTheme: const ListTileThemeData(selectedColor: Color(0xFF191A1C)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ),
    home: const RoomListPage(),
  );
}
