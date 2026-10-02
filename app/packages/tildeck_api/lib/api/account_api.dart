//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class AccountApi {
  AccountApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Approve
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> approveDeviceWithHttpInfo(String deviceId, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/devices/{device_id}/approve'
      .replaceAll('{device_id}', deviceId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Approve
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> approveDevice(String deviceId, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await approveDeviceWithHttpInfo(deviceId, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Change Password
  ///
  /// Re-wraps the same vault key under a new master password. Every other device is signed out unless the user asks to keep them.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PasswordChange] passwordChange (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> changePasswordWithHttpInfo(PasswordChange passwordChange, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/password';

    // ignore: prefer_final_locals
    Object? postBody = passwordChange;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Change Password
  ///
  /// Re-wraps the same vault key under a new master password. Every other device is signed out unless the user asks to keep them.
  ///
  /// Parameters:
  ///
  /// * [PasswordChange] passwordChange (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> changePassword(PasswordChange passwordChange, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await changePasswordWithHttpInfo(passwordChange, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Claim
  ///
  /// The pending device collects its approval with the claim token only it has: its device token and the wrapped vault key.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ClaimRequest] claimRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> claimDeviceWithHttpInfo(ClaimRequest claimRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/devices/claim';

    // ignore: prefer_final_locals
    Object? postBody = claimRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Claim
  ///
  /// The pending device collects its approval with the claim token only it has: its device token and the wrapped vault key.
  ///
  /// Parameters:
  ///
  /// * [ClaimRequest] claimRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<SignedIn?> claimDevice(ClaimRequest claimRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await claimDeviceWithHttpInfo(claimRequest, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SignedIn',) as SignedIn;
    
    }
    return null;
  }

  /// Recovery Complete
  ///
  /// Sets a new master password with the recovery key, signs out every device, and signs in this one.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [RecoveryComplete] recoveryComplete (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> completeRecoveryWithHttpInfo(RecoveryComplete recoveryComplete, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/recovery/complete';

    // ignore: prefer_final_locals
    Object? postBody = recoveryComplete;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Recovery Complete
  ///
  /// Sets a new master password with the recovery key, signs out every device, and signs in this one.
  ///
  /// Parameters:
  ///
  /// * [RecoveryComplete] recoveryComplete (required):
  ///
  /// * [int] tildeckProtocol:
  Future<SignedIn?> completeRecovery(RecoveryComplete recoveryComplete, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await completeRecoveryWithHttpInfo(recoveryComplete, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SignedIn',) as SignedIn;
    
    }
    return null;
  }

  /// Confirm Totp
  ///
  /// Turns two-factor sign-in on with a code from the new secret.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [TotpCode] totpCode (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> confirmTotpWithHttpInfo(TotpCode totpCode, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/totp/confirm';

    // ignore: prefer_final_locals
    Object? postBody = totpCode;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Confirm Totp
  ///
  /// Turns two-factor sign-in on with a code from the new secret.
  ///
  /// Parameters:
  ///
  /// * [TotpCode] totpCode (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> confirmTotp(TotpCode totpCode, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await confirmTotpWithHttpInfo(totpCode, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Disable Totp
  ///
  /// Turns two-factor sign-in off; a current code proves the authenticator.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [TotpCode] totpCode (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> disableTotpWithHttpInfo(TotpCode totpCode, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/totp/disable';

    // ignore: prefer_final_locals
    Object? postBody = totpCode;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Disable Totp
  ///
  /// Turns two-factor sign-in off; a current code proves the authenticator.
  ///
  /// Parameters:
  ///
  /// * [TotpCode] totpCode (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> disableTotp(TotpCode totpCode, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await disableTotpWithHttpInfo(totpCode, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Get Account
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> getAccountWithHttpInfo({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Get Account
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<AccountView?> getAccount({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await getAccountWithHttpInfo(tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AccountView',) as AccountView;
    
    }
    return null;
  }

  /// Prelogin
  ///
  /// The KDF parameters for an address. An address without an account gets stable made-up parameters, so the answer does not reveal which exist.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PreloginRequest] preloginRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> preloginWithHttpInfo(PreloginRequest preloginRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/prelogin';

    // ignore: prefer_final_locals
    Object? postBody = preloginRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Prelogin
  ///
  /// The KDF parameters for an address. An address without an account gets stable made-up parameters, so the answer does not reveal which exist.
  ///
  /// Parameters:
  ///
  /// * [PreloginRequest] preloginRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<PreloginResponse?> prelogin(PreloginRequest preloginRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await preloginWithHttpInfo(preloginRequest, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PreloginResponse',) as PreloginResponse;
    
    }
    return null;
  }

  /// Register
  ///
  /// Creates an account and signs in the registering device, which created the vault. Syncing waits until the email address is confirmed.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [RegisterRequest] registerRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> registerWithHttpInfo(RegisterRequest registerRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/register';

    // ignore: prefer_final_locals
    Object? postBody = registerRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Register
  ///
  /// Creates an account and signs in the registering device, which created the vault. Syncing waits until the email address is confirmed.
  ///
  /// Parameters:
  ///
  /// * [RegisterRequest] registerRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<SignedIn?> register(RegisterRequest registerRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await registerWithHttpInfo(registerRequest, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SignedIn',) as SignedIn;
    
    }
    return null;
  }

  /// Resend Verification
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> resendVerificationWithHttpInfo({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/verify-email/resend';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Resend Verification
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> resendVerification({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await resendVerificationWithHttpInfo(tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Revoke
  ///
  /// Revokes a device (the current one signs out). Its token stops working immediately.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> revokeDeviceWithHttpInfo(String deviceId, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/devices/{device_id}/revoke'
      .replaceAll('{device_id}', deviceId);

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Revoke
  ///
  /// Revokes a device (the current one signs out). Its token stops working immediately.
  ///
  /// Parameters:
  ///
  /// * [String] deviceId (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<void> revokeDevice(String deviceId, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await revokeDeviceWithHttpInfo(deviceId, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// Signin
  ///
  /// An active device receives its token and the wrapped vault key. A device the account does not know becomes pending and gets a one-time claim token; it receives nothing else until another device or an email link approves it.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [SigninRequest] signinRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> signinWithHttpInfo(SigninRequest signinRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/signin';

    // ignore: prefer_final_locals
    Object? postBody = signinRequest;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Signin
  ///
  /// An active device receives its token and the wrapped vault key. A device the account does not know becomes pending and gets a one-time claim token; it receives nothing else until another device or an email link approves it.
  ///
  /// Parameters:
  ///
  /// * [SigninRequest] signinRequest (required):
  ///
  /// * [int] tildeckProtocol:
  Future<SigninResult?> signin(SigninRequest signinRequest, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await signinWithHttpInfo(signinRequest, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'SigninResult',) as SigninResult;
    
    }
    return null;
  }

  /// Recovery Start
  ///
  /// Proves the recovery key and returns the vault key wrapped by it.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [RecoveryStart] recoveryStart (required):
  ///
  /// * [int] tildeckProtocol:
  Future<Response> startRecoveryWithHttpInfo(RecoveryStart recoveryStart, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/recovery/start';

    // ignore: prefer_final_locals
    Object? postBody = recoveryStart;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Recovery Start
  ///
  /// Proves the recovery key and returns the vault key wrapped by it.
  ///
  /// Parameters:
  ///
  /// * [RecoveryStart] recoveryStart (required):
  ///
  /// * [int] tildeckProtocol:
  Future<RecoveryWrap?> startRecovery(RecoveryStart recoveryStart, { int? tildeckProtocol, Future<void>? abortTrigger, }) async {
    final response = await startRecoveryWithHttpInfo(recoveryStart, tildeckProtocol: tildeckProtocol, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'RecoveryWrap',) as RecoveryWrap;
    
    }
    return null;
  }

  /// Start Totp
  ///
  /// A new secret for two-factor sign-in. Nothing changes until a code from it is confirmed.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> startTotpWithHttpInfo({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/account/totp/start';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (tildeckProtocol != null) {
      headerParams[r'Tildeck-Protocol'] = parameterToString(tildeckProtocol);
    }
    if (authorization != null) {
      headerParams[r'authorization'] = parameterToString(authorization);
    }

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Start Totp
  ///
  /// A new secret for two-factor sign-in. Nothing changes until a code from it is confirmed.
  ///
  /// Parameters:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<TotpEnrollment?> startTotp({ int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await startTotpWithHttpInfo(tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'TotpEnrollment',) as TotpEnrollment;
    
    }
    return null;
  }
}
