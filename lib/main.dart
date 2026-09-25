import 'package:flutter/material.dart';
import 'services/wake_word_service.dart';
import 'services/tts_service.dart';
import 'utils/permissions_helper.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Demande des permissions nécessaires (micro, notifications, batterie).
  await PermissionsHelper.requestAll();

  // 2. Initialise le TTS (prépare le moteur de synthèse vocale).
  await TtsService.instance.init();

  // 3. Démarre le service d'arrière-plan qui écoute en continu le
  //    mot-clé « Banque Parlante », y compris application fermée.
  await initializeWakeWordService();

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
        colorSchemeSeed: const Color(0xFFE8A33D),
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
      ),
      // La logique de bienvenue / enrôlement / empreinte est gérée en
      // interne par HomeScreen selon l'état persistant (OnboardingStorage).
      home: const HomeScreen(),
    );
  }
}
