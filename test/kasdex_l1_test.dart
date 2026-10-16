import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;
import 'package:k_force/src/kasdex_l1.dart';

void main() {
  final pool = <String, Object?>{
    'id': '42' * 32,
    'name': 'KasDex L1 Pilot',
    'ticker': 'PILOT',
    'supply': 1000000,
    'pool_covid': '42' * 32,
    'tok_covid': '41' * 32,
    'network': 'kaspa-mainnet',
    'synced': true,
    'retired': false,
    'reserve_kas': 123000000,
    'reserve_tok': 456000,
  };

  test('mem-parsing pool KasDex mainnet dan menolak network lain', () {
    final parsed = KasDexL1Pool.fromJson(pool);

    expect(parsed.id, '42' * 32);
    expect(parsed.name, 'KasDex L1 Pilot');
    expect(parsed.supply, BigInt.from(1000000));
    expect(parsed.reserveKasSompi, BigInt.from(123000000));
    expect(parsed.reserveToken, BigInt.from(456000));
    expect(
      () => KasDexL1Pool.fromJson({...pool, 'network': 'kaspa-testnet'}),
      throwsFormatException,
    );
  });

  test(
    'memanggil endpoint pool, quote, dan saldo KasDex L1 yang benar',
    () async {
      final requests = <http.Request>[];
      final address = kaspa.Address.publicKey(
        prefix: kaspa.AddressPrefix.kaspa,
        publicKey: Uint8List(32)..fillRange(0, 32, 1),
      ).encoded;
      final repository = KasDexL1Repository(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/l1/pools')) {
            return http.Response(jsonEncode([pool]), 200);
          }
          if (request.url.path.endsWith('/l1/health')) {
            return http.Response(
              jsonEncode({
                'network': 'mainnet',
                'pilot': true,
                'status': 'ok',
                'node_connected': true,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'status': 'ok', 'pool': pool['id']}),
            200,
          );
        }),
      );
      addTearDown(repository.close);

      expect((await repository.fetchHealth())['network'], 'mainnet');
      expect((await repository.fetchPools()).single.ticker, 'PILOT');
      await repository.fetchPool('42' * 32);
      await repository.quote(
        direction: 'kasForTok',
        amountInSompi: BigInt.from(100000000),
        poolId: '42' * 32,
      );
      await repository.fetchBalance(address);

      expect(requests.map((request) => request.url.path).toList(), [
        '/l1m-api/l1/health',
        '/l1m-api/l1/pools',
        '/l1m-api/l1/pool',
        '/l1m-api/l1/quote',
        '/l1m-api/l1/balance',
      ]);
      expect(requests[2].url.queryParameters['pool'], '42' * 32);
      expect(requests[3].url.queryParameters, {
        'direction': 'kasForTok',
        'amount_in': '100000000',
        'pool': '42' * 32,
      });
      expect(requests[4].url.queryParameters['address'], address);
    },
  );

  test('melaporkan status error KasDex alih-alih data sukses palsu', () async {
    final repository = KasDexL1Repository(
      client: MockClient(
        (_) async => http.Response('{"error":"pilot disabled"}', 503),
      ),
    );
    addTearDown(repository.close);

    await expectLater(
      repository.fetchPools(),
      throwsA(
        isA<KasDexL1HttpException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.detail, 'detail', 'pilot disabled'),
      ),
    );
  });
}
