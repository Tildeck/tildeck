//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class SyncApi {
  SyncApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Pull
  ///
  /// Every record, tombstones included, stored after revision `since`, in revision order.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] since:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> pullRecordsWithHttpInfo({ int? since, int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/sync/records';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (since != null) {
      queryParams.addAll(_queryParams('', 'since', since));
    }

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

  /// Pull
  ///
  /// Every record, tombstones included, stored after revision `since`, in revision order.
  ///
  /// Parameters:
  ///
  /// * [int] since:
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<PullResponse?> pullRecords({ int? since, int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await pullRecordsWithHttpInfo(since: since, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PullResponse',) as PullResponse;
    
    }
    return null;
  }

  /// Push
  ///
  /// Stores each change that is exactly the next version of its record (1 for a new record) and reports the others as conflicts with the current record. Revisions are assigned in one transaction per push, with the account row locked, so they never collide or go backwards.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [PushRequest] pushRequest (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<Response> pushRecordsWithHttpInfo(PushRequest pushRequest, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final path = r'/api/sync/records';

    // ignore: prefer_final_locals
    Object? postBody = pushRequest;

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

  /// Push
  ///
  /// Stores each change that is exactly the next version of its record (1 for a new record) and reports the others as conflicts with the current record. Revisions are assigned in one transaction per push, with the account row locked, so they never collide or go backwards.
  ///
  /// Parameters:
  ///
  /// * [PushRequest] pushRequest (required):
  ///
  /// * [int] tildeckProtocol:
  ///
  /// * [String] authorization:
  Future<PushResponse?> pushRecords(PushRequest pushRequest, { int? tildeckProtocol, String? authorization, Future<void>? abortTrigger, }) async {
    final response = await pushRecordsWithHttpInfo(pushRequest, tildeckProtocol: tildeckProtocol, authorization: authorization, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'PushResponse',) as PushResponse;
    
    }
    return null;
  }
}
