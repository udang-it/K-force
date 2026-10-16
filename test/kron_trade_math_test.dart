import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/src/kron_trade_math.dart';

void main() {
  final curve = KronCurveState(
    realKas: BigInt.from(100000000),
    tokenReserve: BigInt.from(1000),
    vKas: BigInt.from(1000),
    graduationKas: BigInt.from(1000000000),
    creatorFeeBps: BigInt.from(100),
    platformFeeBps: BigInt.from(100),
  );
  final pool = KronPoolState(
    kasReserve: BigInt.from(1000),
    tokenReserve: BigInt.from(100000),
    totalShares: BigInt.from(10000),
  );
  final poolParams = KronPoolParams(
    creatorFeeBps: BigInt.from(100),
    platformFeeBps: BigInt.from(100),
    lpFeeBps: BigInt.from(100),
    lockedShares: BigInt.from(1000),
  );

  test('curve quotes match the KRON integer curve equations', () {
    final buy = quoteKronCurveBuy(curve, BigInt.from(10000000));
    expect(buy, isNotNull);
    expect(buy!.kasIn, BigInt.from(10000000));
    expect(buy.tokenOut, BigInt.from(9));
    expect(buy.creatorFee, BigInt.from(20000000));
    expect(buy.platformFee, BigInt.from(20000000));
    expect(buy.total, BigInt.from(50000000));
    expect(buy.newRealKas, BigInt.from(110000000));
    expect(buy.newTokenReserve, BigInt.from(991));

    expect(quoteKronCurveSell(curve, BigInt.from(200)), isNull);
  });

  test('curve quotes reject non-executable and value-destroying trades', () {
    expect(quoteKronCurveBuy(curve, BigInt.from(999999)), isNull);
    expect(quoteKronCurveSell(curve, BigInt.one), isNull);
    expect(
      quoteKronCurveBuy(
        KronCurveState(
          realKas: BigInt.from(900000000000000),
          tokenReserve: curve.tokenReserve,
          vKas: curve.vKas,
          graduationKas: curve.graduationKas,
          creatorFeeBps: curve.creatorFeeBps,
          platformFeeBps: curve.platformFeeBps,
        ),
        BigInt.from(1000000),
      ),
      isNull,
    );
  });

  test('pool quotes preserve KRON fee retention and payout rules', () {
    final buy = quoteKronPoolBuy(pool, poolParams, BigInt.from(10000000));
    expect(buy, isNotNull);
    expect(buy!.tokenOut, BigInt.from(891));
    expect(buy.creatorOut, BigInt.from(20000000));
    expect(buy.platformOut, BigInt.from(20000000));
    expect(buy.total, BigInt.from(50000000));
    expect(buy.newKas, BigInt.from(1010));
    expect(buy.newToken, BigInt.from(99109));

    final sell = quoteKronPoolSell(pool, poolParams, BigInt.from(10000));
    expect(sell, isNotNull);
    expect(sell!.kasOut, BigInt.from(89000000));
    expect(sell.net, BigInt.from(49000000));
    expect(sell.newKas, BigInt.from(911));
    expect(sell.newToken, BigInt.from(110000));
  });

  test('curve dev-fund fees are included only when configured', () {
    final quote = quoteKronCurveBuy(
      KronCurveState(
        realKas: BigInt.from(100000000),
        tokenReserve: BigInt.from(1000),
        vKas: BigInt.from(1000),
        graduationKas: BigInt.from(1000000000),
        creatorFeeBps: BigInt.from(100),
        platformFeeBps: BigInt.from(100),
        devFundBps: BigInt.from(100),
      ),
      BigInt.from(10000000),
    );
    expect(quote, isNotNull);
    expect(quote!.devFundFee, BigInt.from(20000000));
    expect(quote.total, BigInt.from(70000000));
  });
}
