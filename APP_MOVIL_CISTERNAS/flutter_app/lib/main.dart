import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/app_controller.dart';
import 'core/app_config.dart';
import 'data/mobile_api.dart';
import 'data/session_store.dart';
import 'presentation/load_screen.dart';
import 'presentation/login_screen.dart';
import 'presentation/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = MobileApi(endpoint: AppConfig.endpoint);
  runApp(
    CisternasApp(
      controller: AppController(api: api, store: SecureSessionStore()),
      onDispose: api.close,
    ),
  );
}

class CisternasApp extends StatefulWidget {
  const CisternasApp({super.key, required this.controller, this.onDispose});
  final AppController controller;
  final VoidCallback? onDispose;

  @override
  State<CisternasApp> createState() => _CisternasAppState();
}

class _CisternasAppState extends State<CisternasApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.onResume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SCPE · Cisternas',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        if (widget.controller.initializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.controller.session != null) {
          return LoadScreen(controller: widget.controller);
        }
        return LoginScreen(controller: widget.controller);
      },
    ),
  );
}
