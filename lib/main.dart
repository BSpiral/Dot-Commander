import 'dart:async';
import 'package:flutter/material.dart';
import 'monetization/ads_service.dart';
import 'ui/command_screen.dart';
import 'pirates/persistence/voyage_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: the SDK queues ad requests until init completes, so
  // the app does not need to block startup on it.
  unawaited(AdsService.initialize());
  runApp(const DotCommanderApp());
}

class DotCommanderApp extends StatelessWidget {
  final VoyageStore? store;
  const DotCommanderApp({super.key, this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dot Commander: Pirates',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xffe7c17a),
      scaffoldBackgroundColor: const Color(0xff0b2330),
      useMaterial3: true,
    ),
    home: CommandScreen(store: store),
  );
}
