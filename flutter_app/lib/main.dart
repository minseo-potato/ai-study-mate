import 'package:flutter/material.dart';
import 'api.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'theme.dart';

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
      scaffoldBackgroundColor: pageBg,
      colorScheme: ColorScheme.fromSeed(seedColor: brand, surface: Colors.white, primary: brand, onPrimary: Colors.white),
      dividerTheme: const DividerThemeData(color: lineColor),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        backgroundColor: ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: lineColor)),
        surfaceTintColor: Colors.transparent, centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: lineColor))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE1E3E8)))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: brand, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16), textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
      chipTheme: ChipThemeData(backgroundColor: Colors.white, selectedColor: brandSoft,
        side: const BorderSide(color: Color(0xFFE1E3E8)), labelStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, color: Color(0xFF3A3D44)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      listTileTheme: const ListTileThemeData(selectedColor: ink),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: brandSoft,
        surfaceTintColor: Colors.transparent, height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontFamily: 'NotoSansKR', fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? ink : mutedInk))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ),
    home: const AuthGate(),
  );
}

/// 저장된 토큰이 있으면 바로 홈으로, 없거나 만료되면 로그인 화면으로.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  bool ready = false;
  Map<String, dynamic>? account;
  @override void initState() {
    super.initState();
    Api.onSignedOut = () { if (mounted) setState(() => account = null); };
    restore();
  }
  Future<void> restore() async {
    await Api.loadToken();
    if (Api.token != null) {
      try { account = await Api.request('GET', '/me') as Map<String, dynamic>; } catch (_) {}
    }
    if (mounted) setState(() => ready = true);
  }
  Future<void> signOut() async {
    try { await Api.request('POST', '/auth/logout'); } catch (_) {}
    await Api.saveToken(null);
    if (mounted) setState(() => account = null);
  }
  @override Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (account == null) return LoginPage(onSignedIn: (data) => setState(() => account = data));
    return HomeShell(key: ValueKey(account!['user']['id']), account: account!, onSignOut: signOut);
  }
}
