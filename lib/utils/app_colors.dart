import 'package:flutter/material.dart';

/// -----------------------------------------------------------------------
/// Charte graphique officielle de BanqueParle.
///
/// RÈGLE STRICTE : aucune couleur en dehors de cette palette ne doit être
/// utilisée nulle part dans l'application (pas de Colors.white, Colors.red,
/// Colors.grey, etc.). Toute variation (transparence, halo lumineux) doit
/// dériver de l'une des 4 couleurs ci-dessous via .withOpacity().
///
/// Source : cahier des charges §05 (Navy / Amber / Cream) +
/// carte couleur fournie "Vert Émeraude #34A853" (Succès & Statut).
/// -----------------------------------------------------------------------
class AppColors {
  AppColors._();

  /// Fond principal de l'application.
  static const Color navy = Color(0xFF0F1B2D);

  /// Accentuation — bouton micro central, actions primaires.
  static const Color amber = Color(0xFFE8A33D);

  /// Texte principal sur fond sombre.
  static const Color cream = Color(0xFFF5F3EC);

  /// Succès & Statut : disponibilité, bon fonctionnement, confirmation
  /// (RGB 52, 168, 83 — carte officielle fournie).
  static const Color emerald = Color(0xFF34A853);

  // --- Variantes translucides, dérivées UNIQUEMENT des 4 couleurs ci-dessus ---
  static Color creamFaint([double opacity = 0.08]) => cream.withOpacity(opacity);
  static Color navyFaint([double opacity = 0.4]) => navy.withOpacity(opacity);
  static Color amberFaint([double opacity = 0.4]) => amber.withOpacity(opacity);
  static Color emeraldFaint([double opacity = 0.4]) => emerald.withOpacity(opacity);
}
