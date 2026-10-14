import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/session_controller.dart';
import 'theme/app_theme.dart';
import 'ui/screens/connect_screen.dart';
import 'ui/screens/server_screen.dart';

class SharkordApp extends StatelessWidget {
  const SharkordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SessionController>(
      create: (_) => SessionController()..bootstrap(),
      child: MaterialApp(
        title: 'Sharkord',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();

    return switch (controller.phase) {
      SessionPhase.starting => const _Splash(),
      SessionPhase.unauthenticated ||
      SessionPhase.failed ||
      SessionPhase.connecting => ConnectScreen(controller: controller),
      SessionPhase.ready => ServerScreen(controller: controller),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
