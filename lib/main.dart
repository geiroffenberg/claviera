import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAssetLicenses();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ClavieraApp());
}

void registerAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/fonts/LICENSE-Bravura.txt',
    );
    yield LicenseEntryWithLineBreaks(['Bravura music font'], text);
  });
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'android/app/src/main/assets/piano/README.txt',
    );
    yield LicenseEntryWithLineBreaks(['Piano samples'], text);
  });
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
