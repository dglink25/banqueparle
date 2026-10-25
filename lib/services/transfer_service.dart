import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';

import '../utils/db_error.dart';
import '../utils/onboarding_storage.dart';

/// -----------------------------------------------------------------------
/// TransferService
///
/// Toutes les operations bancaires passent par ce service. Il se connecte
/// a Neon avec le role PostgreSQL propre au client (jamais un role
/// partage) et n'appelle QUE des fonctions de la base (transfer_funds,
/// get_balance, get_history, generate_otp, update_owner_name). L'application
/// ne construit ni n'envoie jamais elle-meme un UPDATE sur les soldes :
/// toute la logique de controle vit dans la base (voir sql/schema.sql),
/// hors d'atteinte d'une modification cote client.
///
/// Les valeurs numeriques sont converties en double precision / text
/// cote SQL, afin que l'application ne manipule que des types simples.
/// -----------------------------------------------------------------------
class TransferService {
  static const _storage = FlutterSecureStorage();

  static const _neonHost = String.fromEnvironment('NEON_HOST');
  static const _neonDatabase =
      String.fromEnvironment('NEON_DATABASE', defaultValue: 'neondb');

  /// Ouvre une connexion avec le role du client, execute [action], puis
  /// referme toujours la connexion. Renvoie null si la base n'est pas
  /// configuree ou si le compte n'est pas encore activé sur ce telephone.
  static Future<T?> _withConnection<T>(
    Future<T> Function(Connection conn) action,
  ) async {
    if (_neonHost.isEmpty) return null;
    final role = await _storage.read(key: 'db_role_name');
    final password = await _storage.read(key: 'db_role_password');
    if (role == null || password == null) return null;

    final conn = await Connection.open(
      Endpoint(
        host: _neonHost,
        port: 5432,
        database: _neonDatabase,
        username: role,
        password: password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.require),
    );
    try {
      return await action(conn);
    } finally {
      await conn.close();
    }
  }

  /// Memorise le detail technique de la derniere erreur (affiche a
  /// l'ecran pour le diagnostic).
  static Future<void> _record(Object e) async {
    await OnboardingStorage.setLastDbError(describeDbError(e).detail);
  }

  static Future<TransferResult> transfer({
    required String toAccount,
    required double amount,
  }) async {
    try {
      final balance = await _withConnection<double>((conn) async {
        // Le montant transite en texte puis est converti en numeric par
        // la base : aucune ambiguite d'encodage cote application.
        final result = await conn.execute(
          Sql.named(
            'SELECT new_balance::double precision AS new_balance '
            'FROM transfer_funds(@to, CAST(CAST(@amount AS text) AS numeric))',
          ),
          parameters: {'to': toAccount, 'amount': amount.toStringAsFixed(2)},
        );
        return (result.first.toColumnMap()['new_balance'] as num).toDouble();
      });

      if (balance == null) {
        return TransferResult(
          false,
          'Votre compte n\'est pas encore activé pour les opérations '
          'bancaires.',
        );
      }
      return TransferResult(
        true,
        'Virement effectué avec succès.',
        newBalance: balance,
      );
    } catch (e) {
      await _record(e);
      return TransferResult(false, _mapError(e));
    }
  }

  static Future<double?> getBalance() async {
    try {
      return await _withConnection<double>((conn) async {
        final result = await conn
            .execute('SELECT get_balance()::double precision AS b');
        return (result.first.toColumnMap()['b'] as num).toDouble();
      });
    } catch (e) {
      await _record(e);
      return null;
    }
  }

  /// Dernieres operations (envoyees ou recues), de la plus recente a la
  /// plus ancienne. Renvoie null en cas d'erreur (reseau, compte inactif).
  static Future<List<HistoryEntry>?> getHistory({int limit = 3}) async {
    try {
      return await _withConnection<List<HistoryEntry>>((conn) async {
        final result = await conn.execute(
          Sql.named('SELECT * FROM get_history(@n)'),
          parameters: {'n': limit},
        );
        return result.map((row) {
          final m = row.toColumnMap();
          return HistoryEntry(
            sent: m['tx_direction'] == 'sent',
            otherAccount: m['other_account'] as String,
            otherName: m['other_name'] as String,
            amount: (m['tx_amount'] as num).toDouble(),
            date: DateTime.fromMillisecondsSinceEpoch(
              ((m['tx_epoch'] as num).toDouble() * 1000).round(),
            ),
          );
        }).toList();
      });
    } catch (e) {
      await _record(e);
      return null;
    }
  }

  /// Code a usage unique de 6 chiffres, genere par la base de donnees.
  static Future<OtpResult> generateOtp() async {
    try {
      final code = await _withConnection<String>((conn) async {
        final result = await conn.execute('SELECT generate_otp() AS code');
        return result.first.toColumnMap()['code'] as String;
      });
      if (code == null) {
        return OtpResult(
          null,
          'Votre compte n\'est pas encore activé pour les opérations '
          'bancaires.',
        );
      }
      return OtpResult(code, null);
    } catch (e) {
      await _record(e);
      if (e.toString().contains('OTP_RATE_LIMIT')) {
        return OtpResult(
          null,
          'Trop de codes demandes. Patientez quelques minutes avant d\'en '
          'demander un nouveau.',
        );
      }
      return OtpResult(null, describeDbError(e).spoken);
    }
  }

  /// Synchronise le nom du titulaire cote base. Renvoie false en cas
  /// d'echec (l'appelant en informe l'utilisateur).
  static Future<bool> updateOwnerName(String name) async {
    try {
      final ok = await _withConnection<bool>((conn) async {
        await conn.execute(
          Sql.named('SELECT update_owner_name(@name)'),
          parameters: {'name': name},
        );
        return true;
      });
      return ok ?? false;
    } catch (e) {
      await _record(e);
      return false;
    }
  }

  static String _mapError(Object error) {
    final raw = error.toString();
    if (raw.contains('INSUFFICIENT_BALANCE')) {
      return 'Solde insuffisant pour effectuer ce virement.';
    }
    if (raw.contains('RECIPIENT_NOT_FOUND')) {
      return 'Ce numéro de compte destinataire est introuvable.';
    }
    if (raw.contains('SAME_ACCOUNT')) {
      return 'Impossible de faire un virement vers votre propre compte.';
    }
    if (raw.contains('INVALID_AMOUNT')) {
      return 'Le montant indiqué n\'est pas valide.';
    }
    // Erreur technique (reseau, base, identifiants) : dit la vraie cause.
    return 'Le virement a échoué. ${describeDbError(error).spoken}';
  }
}

class TransferResult {
  final bool success;
  final String message;
  final double? newBalance;
  TransferResult(this.success, this.message, {this.newBalance});
}

class HistoryEntry {
  final bool sent;
  final String otherAccount;
  final String otherName;
  final double amount;
  final DateTime date;
  HistoryEntry({
    required this.sent,
    required this.otherAccount,
    required this.otherName,
    required this.amount,
    required this.date,
  });
}

class OtpResult {
  final String? code;
  final String? error;
  OtpResult(this.code, this.error);
}
