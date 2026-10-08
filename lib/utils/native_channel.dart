import 'package:flutter/services.dart';

/// Canal vers le code Android natif (MainActivity.kt) : reglages systeme
/// et appel telephonique.
const MethodChannel kNativeChannel =
    MethodChannel('com.banqueparle.banqueparle/settings');
