import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';

import '../utils/db_error.dart';
import '../utils/onboarding_storage.dart';

/// -----------------------------------------------------------------------
/// AccountProvisioningService
///
/// Cree, une seule fois par client, un role PostgreSQL dedie a privileges
/// minimaux sur Neon (voir sql/schema.sql : fonction create_customer_role).
/// Ce role est ensuite le SEUL identifiant utilise par l'application pour
/// toutes les operations bancaires de ce client -- jamais le role
/// provisionneur, qui n'a lui-meme aucun acces direct aux donnees.
///
/// Les parametres de connexion sont fournis au moment du build via
/// --dart-define (voir .github/workflows/build-apk.yml et README.md),
/// jamais codes en dur dans le depot.
/// -----------------------------------------------------------------------
class AccountProvisioningService {
  static const _storage = FlutterSecureStorage();

  static const _neonHost = String.fromEnvironment('NEON_HOST');
  static const _neonDatabase =
      String.fromEnvironment('NEON_DATABASE', defaultValue: 'neondb');
  static const _provisionerUser =
      String.fromEnvironment('NEON_PROVISIONER_USER');
  static const _provisionerPassword =
      String.fromEnvironment('NEON_PROVISIONER_PASSWORD');

  static bool get isConfigured =>
      _neonHost.isNotEmpty &&
      _provisionerUser.isNotEmpty &&
      _provisionerPassword.isNotEmpty;

  static Future<bool> isProvisioned() async {
    final pwd = await _storage.read(key: 'db_role_password');
    return pwd != null && pwd.isNotEmpty;
  }

  /// Cree le role Postgres dedie a ce client et stocke ses identifiants
  /// dans le stockage securise du telephone (Keystore Android). Renvoie
  /// true en cas de succes.
  static Future<ProvisioningResult> provision({
    required String accountNumber,
    required String ownerName,
  }) async {
    if (!isConfigured) {
      return ProvisioningResult(
        false,
        'La base de donnees n\'est pas configuree sur cette build.',
      );
    }

    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: _neonHost,
          port: 5432,
          database: _neonDatabase,
          username: _provisionerUser,
          password: _provisionerPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.require),
      );

      final result = await conn.execute(
        Sql.named('SELECT create_customer_role(@acc, @name) AS pwd'),
        parameters: {'acc': accountNumber, 'name': ownerName},
      );

      final password = result.first.toColumnMap()['pwd'] as String;
      final roleName =
          'cust_${accountNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';

      await _storage.write(key: 'db_role_name', value: roleName);
      await _storage.write(key: 'db_role_password', value: password);

      await OnboardingStorage.setLastDbError('');
      return ProvisioningResult(true, 'Compte bancaire active avec succes.');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ACCOUNT_ALREADY_EXISTS')) {
        return ProvisioningResult(
          false,
          'Ce numero de compte est deja enregistre.',
        );
      }
      // Dit la vraie cause (base introuvable, script non execute,
      // identifiants refuses, reseau...) au lieu d'un message unique.
      final info = describeDbError(e);
      await OnboardingStorage.setLastDbError(info.detail);
      return ProvisioningResult(false, info.spoken);
    } finally {
      await conn?.close();
    }
  }
}

class ProvisioningResult {
  final bool success;
  final String message;
  ProvisioningResult(this.success, this.message);
}
