import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum KronMarketKind { curve, pool }

class KronMarketListing {
  const KronMarketListing({
    required this.ticker,
    required this.name,
    required this.decimals,
    required this.graduated,
    required this.dormant,
    required this.covenantId,
    required this.holderCount,
    required this.minted,
    required this.priceKas,
    required this.change24hPercent,
    required this.volume24hKas,
    required this.totalValueLockedKas,
    required this.sparkline,
  });

  final String ticker;
  final String name;
  final int decimals;
  final bool graduated;
  final bool dormant;
  final String covenantId;
  final int holderCount;
  final BigInt minted;
  final double? priceKas;
  final double? change24hPercent;
  final double? volume24hKas;
  final double? totalValueLockedKas;
  final List<double> sparkline;

  factory KronMarketListing.fromJson(Map<String, dynamic> json) {
    final ticker = json['tick'];
    final name = json['name'];
    final decimals = _integer(json['dec']);
    final covenantId = json['covenantId'];
    final graduated = json['graduated'];
    final dormant = json['dormant'];
    final holderCount = _integer(json['holderTotal']);
    if (ticker is! String ||
        ticker.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        decimals == null ||
        decimals < 0 ||
        decimals > 18 ||
        covenantId is! String ||
        !_isCovenantId(covenantId) ||
        graduated is! bool ||
        dormant is! bool ||
        holderCount == null ||
        holderCount < 0) {
      throw const FormatException('Data market KRON tidak valid.');
    }
    final sparkline = json['sparkline'];
    if (sparkline != null && sparkline is! List) {
      throw const FormatException('Grafik market KRON tidak valid.');
    }
    return KronMarketListing(
      ticker: ticker,
      name: name,
      decimals: decimals,
      graduated: graduated,
      dormant: dormant,
      covenantId: covenantId,
      holderCount: holderCount,
      minted: _bigInteger(json['minted'], field: 'minted'),
      priceKas: _number(json['price'], field: 'price'),
      change24hPercent: _number(json['change24h'], field: 'change24h'),
      volume24hKas: _number(json['volume24h'], field: 'volume24h'),
      totalValueLockedKas: _number(json['tvl'], field: 'tvl'),
      sparkline: sparkline is List
          ? List.unmodifiable(
              sparkline
                  .map((value) => _requiredNumber(value, 'sparkline'))
                  .toList(),
            )
          : const [],
    );
  }
}

class KronVerifiedToken {
  const KronVerifiedToken({
    required this.ticker,
    required this.name,
    required this.covenantId,
    required this.decimals,
    required this.logoUri,
  });

  final String ticker;
  final String name;
  final String covenantId;
  final int decimals;
  final String? logoUri;

  factory KronVerifiedToken.fromJson(Map<String, dynamic> json) {
    final ticker = json['symbol'];
    final name = json['name'];
    final covenantId = json['covenantId'];
    final decimals = _integer(json['decimals']);
    final extensions = json['extensions'];
    final network = json['network'];
    final logoUri = json['logoURI'];
    if (network != 'mainnet' ||
        ticker is! String ||
        ticker.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        covenantId is! String ||
        !_isCovenantId(covenantId) ||
        decimals == null ||
        decimals < 0 ||
        decimals > 18 ||
        extensions is! Map ||
        extensions['chainVerified'] != true) {
      throw const FormatException('Token registry KRON tidak valid.');
    }
    return KronVerifiedToken(
      ticker: ticker,
      name: name,
      covenantId: covenantId,
      decimals: decimals,
      logoUri: logoUri is String && logoUri.startsWith('https://')
          ? logoUri
          : null,
    );
  }
}

class KronTokenBalance {
  const KronTokenBalance({
    required this.ticker,
    required this.balance,
    required this.decimals,
  });

  final String ticker;
  final BigInt balance;
  final int decimals;

  factory KronTokenBalance.fromJson(Map<String, dynamic> json) {
    final ticker = json['tick'];
    final decimals = _integer(json['dec']);
    if (ticker is! String ||
        ticker.trim().isEmpty ||
        decimals == null ||
        decimals < 0 ||
        decimals > 18) {
      throw const FormatException('Saldo token KRON tidak valid.');
    }
    return KronTokenBalance(
      ticker: ticker,
      balance: _bigInteger(json['balance'], field: 'balance'),
      decimals: decimals,
    );
  }
}

class KronOhlc {
  const KronOhlc({
    required this.timestampSeconds,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final int timestampSeconds;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  factory KronOhlc.fromJson(Map<String, dynamic> json) => KronOhlc(
    timestampSeconds:
        _integer(json['time'] ?? json['t']) ??
        (throw const FormatException('Waktu OHLC KRON tidak valid.')),
    open: _requiredNumber(json['open'] ?? json['o'], 'open'),
    high: _requiredNumber(json['high'] ?? json['h'], 'high'),
    low: _requiredNumber(json['low'] ?? json['l'], 'low'),
    close: _requiredNumber(json['close'] ?? json['c'], 'close'),
    volume: _requiredNumber(json['volume'] ?? json['v'], 'volume'),
  );
}

class KronTrade {
  const KronTrade({
    required this.transactionId,
    required this.timestampSeconds,
    required this.side,
    required this.kind,
    required this.priceKas,
    required this.volumeKas,
  });

  final String transactionId;
  final int timestampSeconds;
  final String side;
  final String kind;
  final double priceKas;
  final double volumeKas;

  factory KronTrade.fromJson(Map<String, dynamic> json) {
    final transactionId = json['txid'];
    final timestamp = _integer(json['ts']);
    final side = json['side'];
    final kind = json['kind'];
    if (transactionId is! String ||
        timestamp == null ||
        side is! String ||
        kind is! String) {
      throw const FormatException('Data transaksi KRON tidak valid.');
    }
    return KronTrade(
      transactionId: transactionId,
      timestampSeconds: timestamp,
      side: side,
      kind: kind,
      priceKas: _requiredNumber(json['price'], 'price'),
      volumeKas: _requiredNumber(json['volume'], 'volume'),
    );
  }
}

class KronDiscoveryRepository {
  KronDiscoveryRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 15);
  static const _indexerBaseUri = 'https://idx.kron.technology/v1/kcc20';
  static const _registryTokenListUri =
      'https://api.kron.technology/api/registry/tokenlist';

  Future<List<KronMarketListing>> fetchMarkets(KronMarketKind kind) async {
    final uri = Uri.parse(
      '$_indexerBaseUri/markets',
    ).replace(queryParameters: {'kind': kind.name});
    final result = await _fetchResult(uri, label: 'Market');
    if (result is! List) {
      throw const FormatException('Daftar market KRON tidak tersedia.');
    }
    return List.unmodifiable(
      result
          .map(
            (item) => KronMarketListing.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Future<List<KronVerifiedToken>> fetchVerifiedTokens() async {
    final uri = Uri.parse(_registryTokenListUri);
    final response = await _get(uri);
    final decoded = _decode(response.body);
    if (decoded is! Map ||
        decoded['network'] != 'mainnet' ||
        decoded['tokens'] is! List) {
      throw const FormatException('Token registry KRON tidak tersedia.');
    }
    return List.unmodifiable(
      (decoded['tokens'] as List)
          .map(
            (item) => KronVerifiedToken.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  Future<List<KronTokenBalance>> fetchPortfolioBalances(
    Iterable<String> addresses,
  ) async {
    final uniqueAddresses = addresses.toSet();
    if (uniqueAddresses.isEmpty) return const [];
    final results = await Future.wait(
      uniqueAddresses.map((address) async {
        final uri = Uri.parse(
          '$_indexerBaseUri/address/${Uri.encodeComponent(address)}/tokenlist',
        );
        final result = await _fetchResult(uri, label: 'Saldo KCC-20');
        if (result is! List) {
          throw const FormatException('Daftar saldo KRON tidak tersedia.');
        }
        return result
            .map(
              (item) => KronTokenBalance.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      }),
    );
    final balances = <String, KronTokenBalance>{};
    for (final addressBalances in results) {
      for (final balance in addressBalances) {
        final existing = balances[balance.ticker];
        if (existing != null && existing.decimals != balance.decimals) {
          throw FormatException(
            'Desimal token ${balance.ticker} berbeda antar alamat.',
          );
        }
        balances[balance.ticker] = KronTokenBalance(
          ticker: balance.ticker,
          balance: (existing?.balance ?? BigInt.zero) + balance.balance,
          decimals: balance.decimals,
        );
      }
    }
    return List.unmodifiable(balances.values.toList());
  }

  Future<KronMarketListing> fetchToken(String ticker) async {
    final uri = Uri.parse(
      '$_indexerBaseUri/token/${Uri.encodeComponent(ticker)}',
    );
    final result = await _fetchResult(uri, label: 'Detail token KRON');
    final tokenJson = result is List && result.isNotEmpty
        ? result.first
        : result;
    if (tokenJson is! Map) {
      throw const FormatException('Detail token KRON tidak tersedia.');
    }
    return KronMarketListing.fromJson(Map<String, dynamic>.from(tokenJson));
  }

  Future<List<KronOhlc>> fetchOhlc(String ticker) async {
    final uri = Uri.parse(
      '$_indexerBaseUri/token/${Uri.encodeComponent(ticker)}/ohlc',
    ).replace(queryParameters: const {'interval': '1h'});
    final result = await _fetchResult(uri, label: 'Grafik KRON');
    if (result is! List) {
      throw const FormatException('Data grafik KRON tidak tersedia.');
    }
    final entries = result
        .map(
          (item) => KronOhlc.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    entries.sort(
      (left, right) => left.timestampSeconds.compareTo(right.timestampSeconds),
    );
    return List.unmodifiable(entries);
  }

  Future<List<KronTrade>> fetchTrades(String ticker) async {
    final uri = Uri.parse(
      '$_indexerBaseUri/token/${Uri.encodeComponent(ticker)}/trades',
    ).replace(queryParameters: const {'offset': '0', 'limit': '20'});
    final result = await _fetchResult(uri, label: 'Transaksi KRON');
    if (result is! List) {
      throw const FormatException('Riwayat transaksi KRON tidak tersedia.');
    }
    return List.unmodifiable(
      result
          .map(
            (item) =>
                KronTrade.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }

  Future<dynamic> _fetchResult(Uri uri, {required String label}) async {
    final response = await _get(uri);
    final decoded = _decode(response.body);
    if (decoded is! Map ||
        decoded['message'] != 'successful' ||
        !decoded.containsKey('result')) {
      throw FormatException('$label tidak tersedia dari KRON.');
    }
    return decoded['result'];
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _requestWithRetry(
      uri,
      () => _client.get(uri, headers: const {'Accept': 'application/json'}),
    );
    if (response.statusCode != 200) {
      throw KronHttpException(uri, response.statusCode);
    }
    return response;
  }

  dynamic _decode(String body) => jsonDecode(body);

  Future<http.Response> _requestWithRetry(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await request().timeout(_timeout);
        if (_isRetryableStatus(response.statusCode) && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return response;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    throw StateError('Koneksi ke KRON gagal untuk $uri: $lastError');
  }

  void close() => _client.close();
}

class KronHttpException implements Exception {
  const KronHttpException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'KRON merespons HTTP $statusCode untuk $uri.';
}

bool _isRetryableStatus(int statusCode) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500;

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num && value.isFinite && value == value.toInt()) {
    return value.toInt();
  }
  return null;
}

double? _number(Object? value, {required String field}) {
  if (value == null) return null;
  final result = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  if (result == null || !result.isFinite) {
    throw FormatException('Nilai $field KRON harus berupa angka terbatas.');
  }
  return result;
}

double _requiredNumber(Object? value, String field) =>
    _number(value, field: field) ??
    (throw FormatException('Field $field KRON tidak tersedia.'));

BigInt _bigInteger(Object? value, {required String field}) {
  final result = switch (value) {
    BigInt() => value,
    int() => BigInt.from(value),
    String() => BigInt.tryParse(value),
    _ => null,
  };
  if (result == null || result < BigInt.zero) {
    throw FormatException('Nilai $field KRON tidak valid.');
  }
  return result;
}

bool _isCovenantId(String value) =>
    RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
