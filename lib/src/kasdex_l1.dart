import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

import 'kaspa_wallet_core.dart';

class KasDexL1Pool {
  const KasDexL1Pool({
    required this.id,
    required this.name,
    required this.ticker,
    required this.supply,
    required this.reserveKasSompi,
    required this.reserveToken,
    required this.synced,
    required this.retired,
    required this.poolCovenantId,
    required this.tokenCovenantId,
  });

  final String id;
  final String name;
  final String ticker;
  final BigInt supply;
  final BigInt reserveKasSompi;
  final BigInt reserveToken;
  final bool synced;
  final bool retired;
  final String poolCovenantId;
  final String tokenCovenantId;

  factory KasDexL1Pool.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final ticker = json['ticker'];
    final supply = _kasDexBigInt(json['supply'], 'supply');
    final reserveKas = _kasDexBigInt(json['reserve_kas'], 'reserve_kas');
    final reserveToken = _kasDexBigInt(json['reserve_tok'], 'reserve_tok');
    final network = json['network'];
    final synced = json['synced'];
    final retired = json['retired'];
    final poolCovid = json['pool_covid'] ?? id;
    final tokenCovid = json['tok_covid'];
    if (id is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        ticker is! String ||
        ticker.trim().isEmpty ||
        network != 'kaspa-mainnet' ||
        synced is! bool ||
        retired is! bool ||
        !_isPoolId(poolCovid) ||
        !_isPoolId(tokenCovid)) {
      throw const FormatException('Data pool KasDex L1 tidak valid.');
    }
    return KasDexL1Pool(
      id: id,
      name: name,
      ticker: ticker,
      supply: supply,
      reserveKasSompi: reserveKas,
      reserveToken: reserveToken,
      synced: synced,
      retired: retired,
      poolCovenantId: poolCovid as String,
      tokenCovenantId: tokenCovid as String,
    );
  }
}

class KasDexL1Quote {
  const KasDexL1Quote({
    required this.direction,
    required this.amountIn,
    required this.amountOut,
    required this.minimumAmountOut,
  });

  final String direction;
  final BigInt amountIn;
  final BigInt amountOut;
  final BigInt minimumAmountOut;
}

class KasDexL1Repository {
  KasDexL1Repository({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _baseUri = Uri.parse('https://kasdex.app/l1m-api');
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;

  Future<Map<String, dynamic>> fetchHealth() async =>
      _kasDexMap(await _get('/l1/health'), 'health');

  Future<List<KasDexL1Pool>> fetchPools() async {
    final result = await _get('/l1/pools');
    if (result is! List) {
      throw const FormatException('Daftar pool KasDex L1 tidak valid.');
    }
    return List.unmodifiable(
      result
          .map((entry) => KasDexL1Pool.fromJson(_kasDexMap(entry, 'pool')))
          .toList(),
    );
  }

  Future<Map<String, dynamic>> fetchPool(String poolId) async {
    if (!_isPoolId(poolId)) {
      throw const FormatException('ID pool KasDex tidak valid.');
    }
    return _kasDexMap(await _get('/l1/pool', query: {'pool': poolId}), 'pool');
  }

  Future<Map<String, dynamic>> quote({
    required String direction,
    required BigInt amountInSompi,
    required String poolId,
  }) async {
    if (!{'kasForTok', 'tokForKas'}.contains(direction) ||
        amountInSompi <= BigInt.zero ||
        !_isPoolId(poolId)) {
      throw ArgumentError('Parameter quote KasDex tidak valid.');
    }
    return _kasDexMap(
      await _get(
        '/l1/quote',
        query: {
          'direction': direction,
          'amount_in': amountInSompi.toString(),
          'pool': poolId,
        },
      ),
      'quote',
    );
  }

  Future<Map<String, dynamic>> fetchBalance(String address) async {
    if (kaspa.Address.tryParse(
          address,
          expectedPrefix: kaspa.AddressPrefix.kaspa,
        ) ==
        null) {
      throw const FormatException('Alamat saldo KasDex harus mainnet.');
    }
    return _kasDexMap(
      await _get('/l1/balance', query: {'address': address}),
      'balance',
    );
  }

  Future<KasDexL1Quote> quoteSwap({
    required KaspaWalletSession session,
    required KasDexL1Pool pool,
    required String direction,
    required BigInt amountIn,
  }) async {
    _validateSwapRequest(direction, amountIn);
    await _ensurePilotReady();
    await session.tradeWalletInfo();
    final currentPool = KasDexL1Pool.fromJson(await fetchPool(pool.id));
    _validateCurrentPool(currentPool, pool);
    final response = await quote(
      direction: direction,
      amountInSompi: amountIn,
      poolId: pool.id,
    );
    final quotePool = response['pool'];
    if (quotePool != pool.id || response['direction'] != direction) {
      throw const FormatException('Quote KasDex berbeda dari pool/arah.');
    }
    final quotedInput = _kasDexBigInt(response['amount_in'], 'amount_in');
    final amountOut = _kasDexBigInt(response['amount_out'], 'amount_out');
    if (quotedInput != amountIn || amountOut <= BigInt.zero) {
      throw const FormatException('Jumlah quote KasDex tidak valid.');
    }
    final maxInput = response['max_amount_in'];
    if (maxInput != null &&
        amountIn > _kasDexBigInt(maxInput, 'max_amount_in')) {
      throw StateError('Jumlah melampaui batas swap KasDex saat ini.');
    }
    return KasDexL1Quote(
      direction: direction,
      amountIn: amountIn,
      amountOut: amountOut,
      minimumAmountOut: amountOut * BigInt.from(9900) ~/ BigInt.from(10000),
    );
  }

  Future<String> swap({
    required KaspaWalletSession session,
    required KasDexL1Pool pool,
    required String direction,
    required BigInt amountIn,
    required KasDexL1Quote reviewedQuote,
  }) async {
    final latestQuote = await quoteSwap(
      session: session,
      pool: pool,
      direction: direction,
      amountIn: amountIn,
    );
    if (reviewedQuote.direction != direction ||
        reviewedQuote.amountIn != amountIn ||
        latestQuote.amountOut < reviewedQuote.minimumAmountOut) {
      throw StateError(
        'Quote KasDex berubah melebihi toleransi; tinjau ulang sebelum swap.',
      );
    }
    final wallet = await session.tradeWalletInfo();
    final address = wallet['receiveAddress'];
    if (address is! String) {
      throw const FormatException('Alamat wallet Kaspa tidak tersedia.');
    }
    final currentPool = KasDexL1Pool.fromJson(await fetchPool(pool.id));
    _validateCurrentPool(currentPool, pool);
    final branches = direction == 'tokForKas'
        ? _tokenBranches(await fetchBalance(address), pool.tokenCovenantId)
        : const <Map<String, Object?>>[];
    final prepared = _kasDexMap(
      await _post('/l1/swap/build', {
        'pool': pool.id,
        'direction': direction,
        'amount_in': _kasDexApiInteger(amountIn),
        'address': address,
      }),
      'swap preparation',
    );
    await _ensurePilotReady();
    final signatures = await session.signKasDexSwap(
      prepared,
      pool: {
        'id': currentPool.id,
        'pool_covid': currentPool.poolCovenantId,
        'tok_covid': currentPool.tokenCovenantId,
      },
      direction: direction,
      amountIn: amountIn,
      minimumAmountOut: reviewedQuote.minimumAmountOut,
      address: address,
      tokenBranches: branches,
    );
    final buildId = prepared['build_id'];
    if (buildId is! String || buildId.isEmpty) {
      throw const FormatException('ID transaksi swap KasDex tidak valid.');
    }
    await _ensurePilotReady();
    final submitted = _kasDexMap(
      await _post('/l1/swap/submit', {
        'build_id': buildId,
        'signatures': signatures,
      }),
      'swap submission',
    );
    final txid = submitted['txid'];
    if (txid is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid)) {
      throw const FormatException(
        'KasDex tidak mengembalikan txid yang valid.',
      );
    }
    return txid;
  }

  Future<String> launchToken({
    required KaspaWalletSession session,
    required String name,
    required String ticker,
    required BigInt supply,
    required BigInt seedToken,
    required BigInt seedKasSompi,
    required int lockDays,
  }) async {
    if (session.profile.networkId != 'mainnet' ||
        name.trim().length < 2 ||
        name.trim().length > 32 ||
        !RegExp(r'^[A-Za-z0-9]{2,8}$').hasMatch(ticker.trim()) ||
        supply < BigInt.from(1000) ||
        seedToken < BigInt.from(100) ||
        seedToken > supply ||
        seedKasSompi < BigInt.from(100000000) ||
        lockDays < 7 ||
        lockDays > 365) {
      throw ArgumentError('Parameter launch KasDex mainnet tidak valid.');
    }

    final health = await _ensurePilotReady();
    final poolCapSompi = _kasDexBigInt(
      health['pool_cap_sompi'],
      'pool_cap_sompi',
    );
    if (seedKasSompi > poolCapSompi) {
      throw ArgumentError(
        'Seed KAS melebihi batas pool KasDex saat ini '
        '(${poolCapSompi ~/ BigInt.from(100000000)} KAS).',
      );
    }
    final wallet = await session.tradeWalletInfo();
    final address = wallet['receiveAddress'];
    if (address is! String) {
      throw const FormatException('Alamat wallet Kaspa tidak tersedia.');
    }
    final request = <String, Object?>{
      'name': name.trim(),
      'ticker': ticker.trim().toUpperCase(),
      'supply': _kasDexApiInteger(supply),
      'seed_tok': _kasDexApiInteger(seedToken),
      'seed_kas': _kasDexApiInteger(seedKasSompi),
      'lock_days': lockDays,
    };
    final prepared = _kasDexMap(
      await _post('/l1/launch/prepare', {...request, 'address': address}),
      'launch preparation',
    );
    await _ensurePilotReady();
    final signatures = await session.signKasDexLaunch(
      prepared,
      requested: request,
      address: address,
    );
    final launchId = prepared['launch_id'];
    if (launchId is! String || launchId.isEmpty) {
      throw const FormatException('ID launch KasDex tidak valid.');
    }
    await _ensurePilotReady();
    final submitted = _kasDexMap(
      await _post('/l1/launch/submit', {
        'launch_id': launchId,
        'signatures': signatures,
      }),
      'launch submission',
    );
    final pool = submitted['pool'];
    final txid = submitted['txid'];
    if (pool is! Map || txid is! String || !_isPoolId(pool['id'])) {
      throw const FormatException(
        'KasDex tidak mengembalikan pool dan transaksi launch yang valid.',
      );
    }
    return txid;
  }

  Future<Map<String, dynamic>> _ensurePilotReady() async {
    final health = await fetchHealth();
    if (health['network'] != 'mainnet' ||
        health['pilot'] != true ||
        health['status'] != 'ok' ||
        health['node_connected'] != true ||
        health['contract_version'] != 5) {
      throw StateError(
        'KasDex L1 pilot belum siap (network=${health['network']}, '
        'status=${health['status']}, '
        'node_connected=${health['node_connected']}, '
        'contract_version=${health['contract_version']}).',
      );
    }
    return health;
  }

  void _validateSwapRequest(String direction, BigInt amountIn) {
    if (!{'kasForTok', 'tokForKas'}.contains(direction) ||
        amountIn <= BigInt.zero) {
      throw ArgumentError('Parameter swap KasDex tidak valid.');
    }
    _kasDexApiInteger(amountIn);
  }

  void _validateCurrentPool(KasDexL1Pool current, KasDexL1Pool expected) {
    if (current.id != expected.id ||
        current.poolCovenantId != expected.poolCovenantId ||
        current.tokenCovenantId != expected.tokenCovenantId ||
        !current.synced ||
        current.retired) {
      throw StateError(
        'Pool KasDex berubah, tidak tersinkron, atau sudah retired.',
      );
    }
  }

  List<Map<String, Object?>> _tokenBranches(
    Map<String, dynamic> balance,
    String tokenCovid,
  ) {
    final tokens = balance['tokens'];
    if (tokens is List) {
      final matches = tokens
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .where(
            (entry) =>
                entry['tok_covid'] is String &&
                (entry['tok_covid'] as String).toLowerCase() ==
                    tokenCovid.toLowerCase(),
          )
          .toList(growable: false);
      if (matches.length == 1) {
        return _parseTokenBranchList(
          matches.single['branches'] ?? balance['tok_branches'],
        );
      }
      if (matches.length > 1) {
        throw const FormatException(
          'Saldo KasDex berisi covenant token duplikat.',
        );
      }
    }
    if (balance['tok_covid'] is String &&
        (balance['tok_covid'] as String).toLowerCase() ==
            tokenCovid.toLowerCase()) {
      return _parseTokenBranchList(balance['tok_branches']);
    }
    final legacyCovid = balance['tok_covid'];
    if (legacyCovid != null && legacyCovid is! String) {
      throw const FormatException('Covenant saldo KasDex tidak valid.');
    }
    if (balance['tok_branches'] is List &&
        (legacyCovid == null ||
            legacyCovid.toLowerCase() == tokenCovid.toLowerCase())) {
      return _parseTokenBranchList(balance['tok_branches']);
    }
    return const [];
  }

  List<Map<String, Object?>> _parseTokenBranchList(Object? value) {
    if (value is! List) {
      throw const FormatException('Daftar branch token KasDex tidak valid.');
    }
    return List.unmodifiable(
      value.map((entry) {
        final branch = _kasDexMap(entry, 'token branch');
        final outpoint = branch['outpoint'];
        if (outpoint is! List ||
            outpoint.length != 2 ||
            outpoint[0] is! String ||
            !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(outpoint[0] as String)) {
          throw const FormatException('Outpoint token KasDex tidak valid.');
        }
        return <String, Object?>{
          'transactionId': outpoint[0],
          'index': _kasDexApiInteger(
            _kasDexBigInt(outpoint[1], 'token branch index'),
          ),
          'amount': _kasDexBigInt(branch['amount'], 'token branch amount'),
        };
      }),
    );
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse(
      '${_baseUri.toString()}$path',
    ).replace(queryParameters: query);
    final response = await _send(
      uri,
      () => _client.get(uri, headers: const {'Accept': 'application/json'}),
    );
    return _decodeResponse(response, uri);
  }

  Future<dynamic> _post(String path, Map<String, Object?> body) async {
    final uri = Uri.parse('${_baseUri.toString()}$path');
    final response = await _send(
      uri,
      () => _client.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
    );
    return _decodeResponse(response, uri);
  }

  Future<http.Response> _send(
    Uri uri,
    Future<http.Response> Function() send,
  ) async {
    try {
      return await send().timeout(_timeout);
    } on TimeoutException catch (error) {
      throw StateError('KasDex tidak merespons untuk $uri: $error');
    } on SocketException catch (error) {
      throw StateError('Koneksi ke KasDex gagal untuk $uri: $error');
    } on http.ClientException catch (error) {
      throw StateError('Koneksi ke KasDex gagal untuk $uri: $error');
    }
  }

  dynamic _decodeResponse(http.Response response, Uri uri) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KasDexL1HttpException(uri, response.statusCode, response.body);
      }
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['error'] : null;
      throw KasDexL1HttpException(
        uri,
        response.statusCode,
        detail is String ? detail : response.body,
      );
    }
    return decoded;
  }

  void close() => _client.close();
}

class KasDexL1HttpException implements Exception {
  const KasDexL1HttpException(this.uri, this.statusCode, this.detail);

  final Uri uri;
  final int statusCode;
  final String detail;

  @override
  String toString() => 'KasDex HTTP $statusCode untuk $uri: $detail';
}

bool _isPoolId(Object? value) =>
    value is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

Map<String, dynamic> _kasDexMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Field $field KasDex tidak valid.');
}

BigInt _kasDexBigInt(Object? value, String field) {
  final parsed = switch (value) {
    int() => BigInt.from(value),
    String() => BigInt.tryParse(value),
    _ => null,
  };
  if (parsed == null || parsed < BigInt.zero) {
    throw FormatException('Field $field KasDex tidak valid.');
  }
  return parsed;
}

int _kasDexApiInteger(BigInt value) {
  if (value > BigInt.from(9007199254740991)) {
    throw RangeError('Nilai launch KasDex melampaui batas integer API.');
  }
  return value.toInt();
}
