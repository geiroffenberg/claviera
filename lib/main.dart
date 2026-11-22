import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ClavieraApp());
}

class ClavieraApp extends StatelessWidget {
  const ClavieraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Claviera',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff496a64)),
      useMaterial3: true,
    ),
    home: const WorkspaceScreen(),
  );
}
