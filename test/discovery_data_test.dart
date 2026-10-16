import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/src/kron_data.dart';

void main() {
  test('mem-parsing market KRON termasuk suplai dan metrik live', () {
    final market = KronMarketListing.fromJson({
      'tick': 'KRON',
      'name': 'Kron Token',
      'dec': 0,
      'graduated': true,
      'dormant': false,
      'covenantId': List.filled(64, 'a').join(),
      'holderTotal': 501,
      'minted': '420000000',
      'price': 0.011552799374430687,
      'change24h': 8.67,
      'volume24h': 115256.41,
      'tvl': 1058329.7,
      'sparkline': [0.01, 0.011],
    });

    expect(market.ticker, 'KRON');
    expect(market.name, 'Kron Token');
    expect(market.minted, BigInt.parse('420000000'));
    expect(market.graduated, isTrue);
    expect(market.priceKas, 0.011552799374430687);
    expect(market.sparkline, [0.01, 0.011]);
  });

  test('hanya menerima token registry KRON terverifikasi di mainnet', () {
    final token = KronVerifiedToken.fromJson({
      'network': 'mainnet',
      'symbol': 'KRON',
      'name': 'Kron Token',
      'covenantId': List.filled(64, 'b').join(),
      'decimals': 0,
      'logoURI': 'https://example.com/kron.png',
      'extensions': {'chainVerified': true},
    });

    expect(token.ticker, 'KRON');
    expect(token.covenantId, List.filled(64, 'b').join());
    expect(token.logoUri, 'https://example.com/kron.png');
    expect(
      () => KronVerifiedToken.fromJson({
        'network': 'mainnet',
        'symbol': 'SCAM',
        'name': 'Unverified',
        'covenantId': List.filled(64, 'c').join(),
        'decimals': 0,
        'extensions': {'chainVerified': false},
      }),
      throwsFormatException,
    );
  });

  test('mem-parsing saldo KCC-20 dan format OHLC KRON', () {
    final balance = KronTokenBalance.fromJson({
      'tick': 'KRON',
      'balance': '10000000000000000000',
      'dec': 8,
    });
    final ohlc = KronOhlc.fromJson({
      'time': 1792114981,
      'open': 0.01,
      'high': 0.02,
      'low': 0.009,
      'close': 0.015,
      'volume': 12.4,
    });

    expect(balance.balance, BigInt.parse('10000000000000000000'));
    expect(balance.decimals, 8);
    expect(ohlc.timestampSeconds, 1792114981);
    expect(ohlc.close, 0.015);
  });

  test('menolak market dan saldo KRON yang tidak valid', () {
    expect(
      () => KronMarketListing.fromJson({'tick': 'KRON'}),
      throwsFormatException,
    );
    expect(
      () => KronTokenBalance.fromJson({'tick': 'KRON', 'balance': '-1'}),
      throwsFormatException,
    );
  });

  test(
    'mengulang permintaan market setelah respons server sementara',
    () async {
      var requests = 0;
      final repository = KronDiscoveryRepository(
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            return http.Response('temporarily unavailable', 503);
          }
          return http.Response(
            '{"message":"successful","result":[]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(repository.close);

      expect(await repository.fetchMarkets(KronMarketKind.curve), isEmpty);
      expect(requests, 2);
    },
  );
}
