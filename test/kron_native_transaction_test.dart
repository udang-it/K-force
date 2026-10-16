import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/src/kron_native_transaction.dart';
import 'package:k_force/src/kron_trade_math.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

void main() {
  test('curve buy scripts match KRON SDK 0.19.2', () {
    final tokenScript = Uint8List(46)
      ..[0] = 32
      ..[33] = 1
      ..[35] = 8
      ..[44] = 1;
    final curveScript = Uint8List(44)
      ..[0] = 1
      ..[2] = 32
      ..[35] = 8;
    final tokenTemplate = KronNativeTokenTemplate(
      script: tokenScript,
      stateStart: 0,
      maxIns: 4,
      maxOuts: 4,
    );
    final curveTemplate = KronNativeCurveTemplate(
      script: curveScript,
      stateStart: 0,
      recipientBound: true,
      creatorFeeOwner: Uint8List(32)..fillRange(0, 32, 3),
      platformFeeOwner: Uint8List(32)..fillRange(0, 32, 4),
      devFundOwner: null,
      creatorFeeBps: BigInt.from(500),
      platformFeeBps: BigInt.from(100),
      devFundBps: null,
    );
    final tokenCovid = Uint8List(32)..fillRange(0, 32, 1);
    final curveCovid = Uint8List(32)..fillRange(0, 32, 2);
    final buyerPublicKey = Uint8List(32)..fillRange(0, 32, 5);
    final state = KronCurveState(
      realKas: BigInt.from(100000000),
      tokenReserve: BigInt.from(1000000),
      vKas: BigInt.from(1000),
      graduationKas: BigInt.from(100000000000),
      creatorFeeBps: BigInt.from(500),
      platformFeeBps: BigInt.from(100),
    );
    final quote = quoteKronCurveBuy(state, BigInt.from(10000000))!;
    final spend = KronNativeTransactionBuilder.curveBuy(
      curveTemplate: curveTemplate,
      tokenTemplate: tokenTemplate,
      curve: KronNativeCurveUtxo(
        transactionId: 'aa' * 32,
        index: 0,
        realKas: state.realKas,
        tokenCovid: tokenCovid,
        tokenReserve: state.tokenReserve,
      ),
      inventory: KronNativeInventoryUtxo(
        transactionId: 'bb' * 32,
        index: 1,
        value: BigInt.from(50000000),
        amount: BigInt.from(1000000),
      ),
      curveCovid: curveCovid,
      tokenCovid: tokenCovid,
      buyerPublicKey: buyerPublicKey,
      presenceWitnessIndex: 2,
      quote: quote,
    );

    expect(quote.tokenOut, BigInt.from(9009));
    expect(
      kaspa.bytesToHex(spend.inputs[0].signatureScript),
      '048096980002312320020202020202020202020202020202020202020202020202020202020202020252030f1f0f00200505050505050505050505050505050505050505050505050505050505050505530231230052200505050505050505050505050505050505050505050505050505050505050505512c01002001010101010101010101010101010101010101010101010101010101010101010840420f0000000000',
    );
    expect(
      kaspa.bytesToHex(spend.inputs[1].signatureScript),
      '4002020202020202020202020202020202020202020202020202020202020202020505050505050505050505050505050505050505050505050505050505050505020203100f1f0f000000000031230000000000000200000001002e20020202020202020202020202020202020202020202020202020202020202020201020840420f00000000000100',
    );
    expect(
      kaspa.bytesToHex(spend.inputs[0].script),
      'aa20b65806aef6d97fc64a81168b74884a5e4450cc296d0f304caa9d3a1b9e8b320987',
    );
    expect(
      kaspa.bytesToHex(spend.outputs[2].script),
      'aa20425b155dc4bcc5efac1108f3c683084977e5cd0c808772ffd2201aa2e896acd987',
    );
  });

  test('template materialization preserves the state layout', () {
    final template = KronNativeTokenTemplate(
      script: Uint8List(46)
        ..[0] = 32
        ..[33] = 1
        ..[35] = 8
        ..[44] = 1,
      stateStart: 0,
      maxIns: 4,
      maxOuts: 4,
    );
    final state = KronNativeTokenState(
      owner: Uint8List(32)..fillRange(0, 32, 9),
      identifierType: 3,
      amount: BigInt.from(987654321),
      isMinter: false,
    );
    final script = KronNativeTransactionBuilder.materializeTokenScript(
      template,
      state,
    );
    final decoded = KronNativeTransactionBuilder.decodeTokenScript(script);

    expect(decoded.owner, state.owner);
    expect(decoded.identifierType, state.identifierType);
    expect(decoded.amount, state.amount);
    expect(decoded.isMinter, state.isMinter);
  });

  test('curve sell scripts match KRON SDK 0.19.2', () {
    final tokenTemplate = KronNativeTokenTemplate(
      script: Uint8List(46)
        ..[0] = 32
        ..[33] = 1
        ..[35] = 8
        ..[44] = 1,
      stateStart: 0,
      maxIns: 4,
      maxOuts: 4,
    );
    final curveTemplate = KronNativeCurveTemplate(
      script: Uint8List(44)
        ..[0] = 1
        ..[2] = 32
        ..[35] = 8,
      stateStart: 0,
      recipientBound: true,
      creatorFeeOwner: Uint8List(32)..fillRange(0, 32, 3),
      platformFeeOwner: Uint8List(32)..fillRange(0, 32, 4),
      devFundOwner: null,
      creatorFeeBps: BigInt.from(500),
      platformFeeBps: BigInt.from(100),
      devFundBps: null,
    );
    final tokenCovid = Uint8List(32)..fillRange(0, 32, 1);
    final curveCovid = Uint8List(32)..fillRange(0, 32, 2);
    final publicKey = Uint8List(32)..fillRange(0, 32, 5);
    final state = KronCurveState(
      realKas: BigInt.from(100000000),
      tokenReserve: BigInt.from(1000000),
      vKas: BigInt.from(1000),
      graduationKas: BigInt.from(100000000000),
      creatorFeeBps: BigInt.from(500),
      platformFeeBps: BigInt.from(100),
    );
    final quote = quoteKronCurveSell(state, BigInt.from(60000))!;
    final spend = KronNativeTransactionBuilder.curveSell(
      curveTemplate: curveTemplate,
      tokenTemplate: tokenTemplate,
      curve: KronNativeCurveUtxo(
        transactionId: 'aa' * 32,
        index: 0,
        realKas: state.realKas,
        tokenCovid: tokenCovid,
        tokenReserve: state.tokenReserve,
      ),
      inventory: KronNativeInventoryUtxo(
        transactionId: 'bb' * 32,
        index: 1,
        value: BigInt.from(50000000),
        amount: state.tokenReserve,
      ),
      sellerTokens: [
        KronNativeTokenUtxo(
          transactionId: 'cc' * 32,
          index: 2,
          value: BigInt.from(50000000),
          state: KronNativeTokenState(
            owner: publicKey,
            identifierType: 3,
            amount: BigInt.from(70000),
            isMinter: false,
          ),
        ),
      ],
      curveCovid: curveCovid,
      tokenCovid: tokenCovid,
      sellerPublicKey: publicKey,
      presenceWitnessIndex: 3,
      quote: quote,
    );

    expect(quote.kasOut, BigInt.from(62000000));
    expect(
      kaspa.bytesToHex(spend.inputs[0].signatureScript),
      '0360ea0004800bb2032002020202020202020202020202020202020202020202020202020202020202025203a02c1000200505050505050505050505050505050505050505050505050505050505050505530210270053200505050505050505050505050505050505050505050505050505050505050505522c01002001010101010101010101010101010101010101010101010101010101010101010840420f0000000000',
    );
    expect(
      kaspa.bytesToHex(spend.inputs[2].signatureScript),
      '400202020202020202020202020202020202020202020202020202020202020202050505050505050505050505050505050505050505050505050505050505050502020310a02c1000000000001027000000000000020000000200032e20050505050505050505050505050505050505050505050505050505050505050501030870110100000000000100',
    );
  });

  test('pool buy scripts match KRON SDK 0.19.2', () {
    final tokenTemplate = KronNativeTokenTemplate(
      script: Uint8List(46)
        ..[0] = 32
        ..[33] = 1
        ..[35] = 8
        ..[44] = 1,
      stateStart: 0,
      maxIns: 4,
      maxOuts: 4,
    );
    final poolTemplate = KronNativePoolTemplate(
      script: Uint8List(93)
        ..[0] = 8
        ..[9] = 8
        ..[18] = 32
        ..[51] = 8
        ..[60] = 32,
      stateStart: 0,
      recipientBound: true,
    );
    final tokenCovid = Uint8List(32)..fillRange(0, 32, 1);
    final poolCovid = Uint8List(32)..fillRange(0, 32, 2);
    final lpCovid = Uint8List(32)..fillRange(0, 32, 4);
    final publicKey = Uint8List(32)..fillRange(0, 32, 5);
    final state = KronPoolState(
      kasReserve: BigInt.from(1000),
      tokenReserve: BigInt.from(1000000),
      totalShares: BigInt.from(1000),
    );
    final quote = quoteKronPoolBuy(
      state,
      KronPoolParams(
        creatorFeeBps: BigInt.from(500),
        platformFeeBps: BigInt.from(100),
        lpFeeBps: BigInt.from(100),
        lockedShares: BigInt.from(100),
      ),
      BigInt.from(10000000),
    )!;
    final spend = KronNativeTransactionBuilder.poolBuy(
      poolTemplate: poolTemplate,
      tokenTemplate: tokenTemplate,
      pool: KronNativePoolUtxo(
        transactionId: 'aa' * 32,
        index: 0,
        tokenTransactionId: 'bb' * 32,
        tokenIndex: 1,
        tokenValue: BigInt.from(50000000),
        state: state,
        poolCovid: poolCovid,
        lpCovid: lpCovid,
      ),
      params: KronNativePoolParams(
        creatorFeeOwner: Uint8List(32)..fillRange(0, 32, 3),
        platformFeeOwner: Uint8List(32)..fillRange(0, 32, 4),
        creatorFeeBps: BigInt.from(500),
        platformFeeBps: BigInt.from(100),
        lpFeeBps: BigInt.from(100),
        lockedShares: BigInt.from(100),
      ),
      mergeTokens: const [],
      tokenCovid: tokenCovid,
      traderPublicKey: publicKey,
      presenceWitnessIndex: 2,
      quote: quote,
    );

    expect(quote.tokenOut, BigInt.from(8919));
    expect(
      kaspa.bytesToHex(spend.inputs[0].signatureScript),
      '5a02d7222002020202020202020202020202020202020202020202020202020202020202025203691f0f002005050505050505050505050505050505050505050505050505050505050505055302d7220052200505050505050505050505050505050505050505050505050505050505050505004c5d08e8030000000000000840420f000000000020010101010101010101010101010101010101010101010101010101010101010108e803000000000000200404040404040404040404040404040404040404040404040404040404040404',
    );
    expect(
      kaspa.bytesToHex(spend.inputs[1].signatureScript),
      '400202020202020202020202020202020202020202020202020202020202020202050505050505050505050505050505050505050505050505050505050505050502020310691f0f0000000000d7220000000000000200000001002e20020202020202020202020202020202020202020202020202020202020202020201020840420f00000000000100',
    );
  });

  test('pool sell scripts match KRON SDK 0.19.2', () {
    final tokenTemplate = KronNativeTokenTemplate(
      script: Uint8List(46)
        ..[0] = 32
        ..[33] = 1
        ..[35] = 8
        ..[44] = 1,
      stateStart: 0,
      maxIns: 4,
      maxOuts: 4,
    );
    final poolTemplate = KronNativePoolTemplate(
      script: Uint8List(93)
        ..[0] = 8
        ..[9] = 8
        ..[18] = 32
        ..[51] = 8
        ..[60] = 32,
      stateStart: 0,
      recipientBound: true,
    );
    final tokenCovid = Uint8List(32)..fillRange(0, 32, 1);
    final poolCovid = Uint8List(32)..fillRange(0, 32, 2);
    final lpCovid = Uint8List(32)..fillRange(0, 32, 4);
    final publicKey = Uint8List(32)..fillRange(0, 32, 5);
    final state = KronPoolState(
      kasReserve: BigInt.from(1000),
      tokenReserve: BigInt.from(1000000),
      totalShares: BigInt.from(1000),
    );
    final poolParams = KronPoolParams(
      creatorFeeBps: BigInt.from(500),
      platformFeeBps: BigInt.from(100),
      lpFeeBps: BigInt.from(100),
      lockedShares: BigInt.from(100),
    );
    final quote = quoteKronPoolSell(state, poolParams, BigInt.from(50000))!;
    final spend = KronNativeTransactionBuilder.poolSell(
      poolTemplate: poolTemplate,
      tokenTemplate: tokenTemplate,
      pool: KronNativePoolUtxo(
        transactionId: 'aa' * 32,
        index: 0,
        tokenTransactionId: 'bb' * 32,
        tokenIndex: 1,
        tokenValue: BigInt.from(50000000),
        state: state,
        poolCovid: poolCovid,
        lpCovid: lpCovid,
      ),
      params: KronNativePoolParams(
        creatorFeeOwner: Uint8List(32)..fillRange(0, 32, 3),
        platformFeeOwner: Uint8List(32)..fillRange(0, 32, 4),
        creatorFeeBps: poolParams.creatorFeeBps,
        platformFeeBps: poolParams.platformFeeBps,
        lpFeeBps: poolParams.lpFeeBps,
        lockedShares: poolParams.lockedShares,
      ),
      traderTokens: [
        KronNativeTokenUtxo(
          transactionId: 'cc' * 32,
          index: 2,
          value: BigInt.from(50000000),
          state: KronNativeTokenState(
            owner: publicKey,
            identifierType: 3,
            amount: BigInt.from(60000),
            isMinter: false,
          ),
        ),
      ],
      tokenCovid: tokenCovid,
      traderPublicKey: publicKey,
      presenceWitnessIndex: 3,
      quote: quote,
    );

    expect(quote.kasOut, BigInt.from(46000000));
    expect(
      kaspa.bytesToHex(spend.inputs[0].signatureScript),
      '012e200202020202020202020202020202020202020202020202020202020202020202520390051000200505050505050505050505050505050505050505050505050505050505050505530210270053200505050505050505050505050505050505050505050505050505050505050505514c5d08e8030000000000000840420f000000000020010101010101010101010101010101010101010101010101010101010101010108e803000000000000200404040404040404040404040404040404040404040404040404040404040404',
    );
    expect(
      kaspa.bytesToHex(spend.inputs[2].signatureScript),
      '40020202020202020202020202020202020202020202020202020202020202020205050505050505050505050505050505050505050505050505050505050505050202031090051000000000001027000000000000020000000200032e20050505050505050505050505050505050505050505050505050505050505050501030860ea0000000000000100',
    );
  });
}
