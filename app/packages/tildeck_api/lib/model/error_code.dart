//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


enum ErrorCode {
  databaseUnavailable._(r'database_unavailable'),
  unsupportedProtocol._(r'unsupported_protocol'),
  registrationClosed._(r'registration_closed'),
  registrationNeedsEmail._(r'registration_needs_email'),
  registrationInviteRequired._(r'registration_invite_required'),
  emailTaken._(r'email_taken'),
  invalidEmail._(r'invalid_email'),
  invalidCredentials._(r'invalid_credentials'),
  accountDisabled._(r'account_disabled'),
  unauthorized._(r'unauthorized'),
  devicePending._(r'device_pending'),
  deviceRevoked._(r'device_revoked'),
  deviceNotFound._(r'device_not_found'),
  invalidToken._(r'invalid_token'),
  tokenExpired._(r'token_expired'),
  recoveryFailed._(r'recovery_failed'),
  rateLimited._(r'rate_limited'),
  invalidRequest._(r'invalid_request'),
  emailUnavailable._(r'email_unavailable'),
  emailNotVerified._(r'email_not_verified'),
  setupNotNeeded._(r'setup_not_needed'),
  invalidSetupToken._(r'invalid_setup_token'),
  invalidTotp._(r'invalid_totp'),
  csrfFailed._(r'csrf_failed'),
  settingLocked._(r'setting_locked'),
  notFound._(r'not_found'),
  ;

  /// Instantiate a new enum with the provided value.
  const ErrorCode._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ErrorCode] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ErrorCode? fromJson(dynamic value) => ErrorCodeTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ErrorCode]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ErrorCode> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ErrorCode>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ErrorCode.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ErrorCode] to String,
/// and [decode] dynamic data back to [ErrorCode].
class ErrorCodeTypeTransformer {
  factory ErrorCodeTypeTransformer() => _instance ??= const ErrorCodeTypeTransformer._();

  const ErrorCodeTypeTransformer._();

  /// Encodes this enum as a value suitable for JSON.
  String encode(ErrorCode data) => data._value;

  /// Returns the instance of [ErrorCode] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ErrorCode? decode(dynamic data, {bool allowNull = true}) {
    if (data is ErrorCode) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'database_unavailable': return ErrorCode.databaseUnavailable;
        case r'unsupported_protocol': return ErrorCode.unsupportedProtocol;
        case r'registration_closed': return ErrorCode.registrationClosed;
        case r'registration_needs_email': return ErrorCode.registrationNeedsEmail;
        case r'registration_invite_required': return ErrorCode.registrationInviteRequired;
        case r'email_taken': return ErrorCode.emailTaken;
        case r'invalid_email': return ErrorCode.invalidEmail;
        case r'invalid_credentials': return ErrorCode.invalidCredentials;
        case r'account_disabled': return ErrorCode.accountDisabled;
        case r'unauthorized': return ErrorCode.unauthorized;
        case r'device_pending': return ErrorCode.devicePending;
        case r'device_revoked': return ErrorCode.deviceRevoked;
        case r'device_not_found': return ErrorCode.deviceNotFound;
        case r'invalid_token': return ErrorCode.invalidToken;
        case r'token_expired': return ErrorCode.tokenExpired;
        case r'recovery_failed': return ErrorCode.recoveryFailed;
        case r'rate_limited': return ErrorCode.rateLimited;
        case r'invalid_request': return ErrorCode.invalidRequest;
        case r'email_unavailable': return ErrorCode.emailUnavailable;
        case r'email_not_verified': return ErrorCode.emailNotVerified;
        case r'setup_not_needed': return ErrorCode.setupNotNeeded;
        case r'invalid_setup_token': return ErrorCode.invalidSetupToken;
        case r'invalid_totp': return ErrorCode.invalidTotp;
        case r'csrf_failed': return ErrorCode.csrfFailed;
        case r'setting_locked': return ErrorCode.settingLocked;
        case r'not_found': return ErrorCode.notFound;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ErrorCodeTypeTransformer? _instance;
}

