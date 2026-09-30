//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library openapi.api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/account_api.dart';
part 'api/health_api.dart';
part 'api/sync_api.dart';

part 'model/accepted.dart';
part 'model/account_view.dart';
part 'model/claim_request.dart';
part 'model/conflict.dart';
part 'model/device_info.dart';
part 'model/device_view.dart';
part 'model/error_body.dart';
part 'model/error_code.dart';
part 'model/kdf_params.dart';
part 'model/liveness.dart';
part 'model/model_sealed.dart';
part 'model/new_password.dart';
part 'model/password_change.dart';
part 'model/prelogin_request.dart';
part 'model/prelogin_response.dart';
part 'model/pull_response.dart';
part 'model/push_request.dart';
part 'model/push_response.dart';
part 'model/readiness.dart';
part 'model/recovery_complete.dart';
part 'model/recovery_start.dart';
part 'model/recovery_wrap.dart';
part 'model/register_request.dart';
part 'model/server_info.dart';
part 'model/signed_in.dart';
part 'model/signin_request.dart';
part 'model/signin_result.dart';
part 'model/stored_record.dart';
part 'model/sync_record.dart';
part 'model/vault_keys.dart';


/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) => pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
