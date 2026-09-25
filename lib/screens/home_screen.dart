import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/tts_service.dart';

class HomeScreen extends StatefulWidget {
  final bool playWelcomeOnStart;
  const HomeScreen({super.key, this.playWelcomeOnStart = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _wakeSub;
  bool _listening = true;

  static const Color kNavy = Color(0xFF0F1B2D);
  static const Color kAmber = Color(0xFFE8A33D);
  static const Color kCream = Color(0xFFF5F3EC);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.playWelcomeOnStart) {
      // Petit délai pour laisser le widget tree se stabiliser.
      Future.delayed(const Duration(milliseconds: 400), () {
        TtsService.instance.speakWelcome();
      });
    }

    // Écoute les événements envoyés par le service d'arrière-plan :
    // dès que le mot-clé est détecté pendant que l'app tourne déjà
    // (au premier plan ou en arrière-plan), on rejoue le message.
    final service = FlutterBackgroundService();
    _wakeSub = service.on('wake_detected').listen((event) {
      TtsService.instance.speakWelcome();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wakeSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quand l'app revient au premier plan (ramenée par le wake-word),
    // on rejoue systématiquement le message de bienvenue.
    if (state == AppLifecycleState.resumed) {
      TtsService.instance.speakWelcome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'BanqueParle',
                style: TextStyle(
                  color: kCream,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Dites « Banque Parlante » à tout moment pour ouvrir '
                'l\'application, même téléphone verrouillé.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kCream.withOpacity(0.7), fontSize: 16),
              ),
              const SizedBox(height: 48),
              _MicButton(color: kAmber, listening: _listening),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.podcasts, color: Color(0xFF34A853), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Écoute active en arrière-plan',
                      style: TextStyle(color: kCream.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => TtsService.instance.speakWelcome(),
                icon: const Icon(Icons.volume_up),
                label: const Text('Rejouer le message de bienvenue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAmber,
                  foregroundColor: kNavy,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final Color color;
  final bool listening;
  const _MicButton({required this.color, required this.listening});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.mic, color: Color(0xFF0F1B2D), size: 56),
    );
  }
}
