import 'dart:ui';

import 'package:flutter/material.dart';
import 'utils/app_colors.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  // 1. Assure l'initialisation du binding Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Gestion globale et résiliente des erreurs pour empêcher la fermeture intempestive de l'application
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformDispatcherError] $error');
    return true; // Erreur interceptée, empêche le crash du processus
  };

  // 3. Monte immédiatement l'application pour afficher l'interface et attacher l'Activity Android
  runApp(const BanqueParleApp());
}

class BanqueParleApp extends StatelessWidget {
  const BanqueParleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BanqueParle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.white,
        fontFamily: 'Roboto',
      ),
      // La logique de bienvenue / enrôlement / empreinte est gérée en
      // interne par HomeScreen selon l'état persistant (OnboardingStorage).
      home: const HomeScreen(),
    );
  }
}
