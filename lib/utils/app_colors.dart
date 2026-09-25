import 'package:flutter/material.dart';

/// Charte graphique de BanqueParle.
///
/// Deux couleurs autorisees dans toute l'application, aucune autre :
///   - Bleu  : #1A73E8
///   - Blanc : #FFFFFF
///
/// Toute variation d'intensite (ombres, surfaces attenuees) doit deriver
/// de la couleur bleue via withOpacity, jamais d'une teinte nouvelle.
class AppColors {
  AppColors._();

  static const Color blue = Color(0xFF1A73E8);
  static const Color white = Color(0xFFFFFFFF);

  static Color blueFaint([double opacity = 0.08]) => blue.withOpacity(opacity);
}
