package com.banqueparle.banqueparle

import io.flutter.embedding.android.FlutterFragmentActivity

/// FlutterFragmentActivity (et non FlutterActivity) est OBLIGATOIRE ici :
/// le plugin local_auth affiche l'invite biométrique native (BiometricPrompt)
/// via un DialogFragment, qui nécessite une FragmentActivity comme hôte.
class MainActivity : FlutterFragmentActivity()
