import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/db.dart';
import 'core/theme.dart';
import 'data/repo.dart';
import 'services/license_service.dart';
import 'ui/activation_page.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.init();
  Repo.i.writable = await LicenseService.load();
  await Repo.i.loadCurrentWarehouse();
  await Repo.i.loadNameMode();
  await Repo.i.refreshArabicNames();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  static final rootKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'المستودع',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorKey: App.rootKey,
        home: LicenseService.activated ? const Shell() : const _Gate(),
      );
}

/// First-run screen before activation. Entering a valid key, or choosing
/// read-only, drops into the app.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  @override
  Widget build(BuildContext context) => ActivationPage(onDone: () {
        Repo.i.writable = LicenseService.activated;
        Repo.i.notify();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
      });
}

//dart run tool/keygen.dart NG1B-Y61W-YHM7
/*
dart run tool/keygen.dart NG1B-Y61W-YHM7
*/

/*
ده يحدث البرنامج 
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
*/

/*
و احفظ الكمه السريه دي عشان دي اللي هطلع بيها مفاتيح 
SK-IZSJFK-OIFXBZ-K1JE08-NDE15X-WZU47N
*/