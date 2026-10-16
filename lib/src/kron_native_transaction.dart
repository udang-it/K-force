import 'dart:convert';
import 'dart:typed_data';

import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

import 'kron_trade_math.dart';

const _kronScale = 1000000;
const _kronDust = 50000000;
const _kronFeeOutputMin = 20000000;

class KronNativeTokenState {
  const KronNativeTokenState({
    required this.owner,
    required this.identifierType,
    required this.amount,
    required this.isMinter,
  });

  final Uint8List owner;
  final int identifierType;
  final BigInt amount;
  final bool isMinter;
}

class KronNativeTemplate {
  const KronNativeTemplate({
    required this.script,
    required this.stateStart,
  });

  final Uint8List script;
  final int stateStart;
}

class KronNativeTokenTemplate extends KronNativeTemplate {
  const KronNativeTokenTemplate({
    required super.script,
    required super.stateStart,
    required this.maxIns,
    required this.maxOuts,
  });

  final int maxIns;
  final int maxOuts;
}

class KronNativeCurveTemplate extends KronNativeTemplate {
  const KronNativeCurveTemplate({
    required super.script,
    required super.stateStart,
    required this.recipientBound,
    required this.creatorFeeOwner,
    required this.platformFeeOwner,
    required this.devFundOwner,
    required this.creatorFeeBps,
    required this.platformFeeBps,
    required this.devFundBps,
  });

  final bool recipientBound;
  final Uint8List creatorFeeOwner;
  final Uint8List platformFeeOwner;
  final Uint8List? devFundOwner;
  final BigInt creatorFeeBps;
  final BigInt platformFeeBps;
  final BigInt? devFundBps;
}

class KronNativePoolTemplate extends KronNativeTemplate {
  const KronNativePoolTemplate({
    required super.script,
    required super.stateStart,
    required this.recipientBound,
  });

  final bool recipientBound;
}

class KronNativePoolParams {
  const KronNativePoolParams({
    required this.creatorFeeOwner,
    required this.platformFeeOwner,
    required this.creatorFeeBps,
    required this.platformFeeBps,
    required this.lpFeeBps,
    required this.lockedShares,
  });

  final Uint8List creatorFeeOwner;
  final Uint8List platformFeeOwner;
  final BigInt creatorFeeBps;
  final BigInt platformFeeBps;
  final BigInt lpFeeBps;
  final BigInt lockedShares;
}

class KronNativeTokenUtxo {
  const KronNativeTokenUtxo({
    required this.transactionId,
    required this.index,
    required this.value,
    required this.state,
  });

  final String transactionId;
  final int index;
  final BigInt value;
  final KronNativeTokenState state;
}

class KronNativeTradeQuote {
  const KronNativeTradeQuote({
    required this.operation,
    required this.market,
    required this.ticker,
    required this.tokenName,
    required this.inputAmount,
    required this.inputUnit,
    required this.outputAmount,
    required this.outputUnit,
    required this.protocolFee,
    required this.networkFee,
    required this.totalKas,
  });

  final String operation;
  final String market;
  final String ticker;
  final String tokenName;
  final BigInt inputAmount;
  final String inputUnit;
  final BigInt outputAmount;
  final String outputUnit;
  final BigInt protocolFee;
  final BigInt networkFee;
  final BigInt totalKas;

  Map<String, Object?> toJson() => {
    'operation': operation,
    'market': market,
    'ticker': ticker,
    'tokenName': tokenName,
    'inputAmount': inputAmount.toString(),
    'inputUnit': inputUnit,
    'outputAmount': outputAmount.toString(),
    'outputUnit': outputUnit,
    'quoteFee': protocolFee.toString(),
    'networkFee': networkFee.toString(),
    'totalKas': totalKas.toString(),
  };
}

class KronNativeBuiltTrade {
  const KronNativeBuiltTrade({
    required this.txJsonString,
    required this.signInputs,
    required this.quote,
  });

  final String txJsonString;
  final List<Map<String, dynamic>> signInputs;
  final KronNativeTradeQuote quote;
}

class KronNativeCurveUtxo {
  const KronNativeCurveUtxo({
    required this.transactionId,
    required this.index,
    required this.realKas,
    required this.tokenCovid,
    required this.tokenReserve,
  });

  final String transactionId;
  final int index;
  final BigInt realKas;
  final Uint8List tokenCovid;
  final BigInt tokenReserve;
}

class KronNativeInventoryUtxo {
  const KronNativeInventoryUtxo({
    required this.transactionId,
    required this.index,
    required this.value,
    required this.amount,
  });

  final String transactionId;
  final int index;
  final BigInt value;
  final BigInt amount;
}

class KronNativePoolUtxo {
  const KronNativePoolUtxo({
    required this.transactionId,
    required this.index,
    required this.tokenTransactionId,
    required this.tokenIndex,
    required this.tokenValue,
    required this.state,
    required this.poolCovid,
    required this.lpCovid,
  });

  final String transactionId;
  final int index;
  final String tokenTransactionId;
  final int tokenIndex;
  final BigInt tokenValue;
  final KronPoolState state;
  final Uint8List poolCovid;
  final Uint8List lpCovid;
}

class KronNativeCovInput {
  const KronNativeCovInput({
    required this.transactionId,
    required this.index,
    required this.value,
    required this.script,
    required this.signatureScript,
    required this.role,
  });

  final String transactionId;
  final int index;
  final BigInt value;
  final Uint8List script;
  final Uint8List signatureScript;
  final String role;
}

class KronNativeCovOutput {
  const KronNativeCovOutput({
    required this.value,
    required this.script,
    this.covenantId,
    this.authorizingInput,
  });

  final BigInt value;
  final Uint8List script;
  final Uint8List? covenantId;
  final int? authorizingInput;
}

class KronNativeSpend {
  const KronNativeSpend({required this.inputs, required this.outputs});

  final List<KronNativeCovInput> inputs;
  final List<KronNativeCovOutput> outputs;
}

class KronNativeTransactionBuilder {
  const KronNativeTransactionBuilder();

  static KronNativeBuiltTrade assemble({
    required KronNativeSpend spend,
    required List<Map<String, Object?>> freshUtxos,
    required List<String> walletAddresses,
    required String changeAddress,
    required double feeRate,
    required KronNativeTradeQuote quote,
  }) {
    if (!feeRate.isFinite || feeRate <= 0) {
      throw ArgumentError.value(feeRate, 'feeRate', 'Biaya transaksi tidak valid.');
    }
    final allowedAddresses = walletAddresses.toSet();
    if (allowedAddresses.isEmpty ||
        allowedAddresses.any(
          (address) =>
              kaspa.Address.tryParse(
                address,
                expectedPrefix: kaspa.AddressPrefix.kaspa,
              ) ==
              null,
        )) {
      throw const FormatException('Alamat wallet mainnet tidak valid.');
    }
    final change = kaspa.Address.tryParse(
      changeAddress,
      expectedPrefix: kaspa.AddressPrefix.kaspa,
    );
    if (change == null || !allowedAddresses.contains(changeAddress)) {
      throw const FormatException('Alamat kembalian bukan milik wallet.');
    }
    if (spend.inputs.isEmpty || spend.outputs.isEmpty) {
      throw const FormatException('Transaksi KRON tidak memiliki input/output.');
    }

    final byOutpoint = <String, Map<String, Object?>>{};
    for (final utxo in freshUtxos) {
      final point = _map(utxo['outpoint'], 'outpoint');
      final txid = _string(point['transactionId'], 'outpoint transactionId');
      final index = _integer(point['index'], 'outpoint index');
      final key = kronNativeOutpointKey(txid, index);
      if (byOutpoint.containsKey(key)) {
        throw const FormatException('Node mengembalikan outpoint UTXO duplikat.');
      }
      byOutpoint[key] = utxo;
    }

    final excluded = <String>{};
    final covenantInputs = <kaspa.RawInput>[];
    final covInputJson = <Map<String, Object?>>[];
    for (final input in spend.inputs) {
      final key = kronNativeOutpointKey(input.transactionId, input.index);
      if (!excluded.add(key)) {
        throw const FormatException('Transaksi KRON memakai outpoint duplikat.');
      }
      final utxo = byOutpoint[key];
      if (utxo == null) {
        throw StateError('UTXO covenant KRON berubah; muat ulang dan coba lagi.');
      }
      final raw = _rawUtxo(utxo);
      if (raw.utxoEntry.amount != input.value ||
          !_sameBytes(
            raw.utxoEntry.scriptPublicKey.scriptPublicKey,
            input.script,
          )) {
        throw StateError('State UTXO covenant KRON berubah; transaksi dibatalkan.');
      }
      final covenantId = raw.utxoEntry.covenantId;
      final serialized = _inputJson(
        raw,
        transactionId: input.transactionId,
        index: input.index,
        signatureScript: input.signatureScript,
        computeBudget: _computeBudget(input.role),
        covenantId: covenantId,
      );
      covenantInputs.add(raw.copyWith(
        previousOutpoint: kaspa.Outpoint(
          transactionId: input.transactionId,
          index: input.index,
        ),
        signatureScript: input.signatureScript,
        sequence: BigInt.zero,
        sigOpCount: 0,
        computeBudget: _computeBudget(input.role),
      ));
      covInputJson.add(serialized);
    }

    final fundingCandidates = <({kaspa.RawInput input, String key})>[];
    for (final entry in freshUtxos) {
      final point = _map(entry['outpoint'], 'outpoint');
      final txid = _string(point['transactionId'], 'outpoint transactionId');
      final index = _integer(point['index'], 'outpoint index');
      final key = kronNativeOutpointKey(txid, index);
      if (excluded.contains(key)) continue;
      final raw = _rawUtxo(entry);
      final covenantId = raw.utxoEntry.covenantId;
      if (!allowedAddresses.contains(raw.address.encoded) ||
          raw.utxoEntry.isCoinbase ||
          covenantId != null) {
        continue;
      }
      fundingCandidates.add((input: raw, key: key));
    }
    fundingCandidates.sort((left, right) {
      final a = left.input.utxoEntry.amount;
      final b = right.input.utxoEntry.amount;
      return b.compareTo(a);
    });
    if (fundingCandidates.isEmpty) {
      throw StateError('Tidak ada UTXO KAS bebas covenant untuk mendanai transaksi.');
    }

    final covInputsValue = covenantInputs.fold<BigInt>(
      BigInt.zero,
      (sum, input) => sum + input.utxoEntry.amount,
    );
    final covenantOutputValue = spend.outputs.fold<BigInt>(
      BigInt.zero,
      (sum, output) => sum + output.value,
    );
    final outputs = spend.outputs.map(_rawOutput).toList(growable: true);
    final outputJson = spend.outputs.map(_outputJson).toList(growable: true);
    final selectedFunding = <kaspa.RawInput>[];
    final selectedFundingJson = <Map<String, Object?>>[];
    final changeScript = kaspa.payToAddressScript(change);
    for (final candidate in fundingCandidates) {
      final point = byOutpoint[candidate.key]!;
      final pointData = _map(point['outpoint'], 'outpoint');
      final txid = _string(pointData['transactionId'], 'outpoint transactionId');
      final index = _integer(pointData['index'], 'outpoint index');
      final rawInput = candidate.input.copyWith(
        previousOutpoint: kaspa.Outpoint(transactionId: txid, index: index),
        signatureScript: Uint8List(0),
        sequence: BigInt.zero,
        sigOpCount: 0,
        computeBudget: 10,
      );
      selectedFunding.add(rawInput);
      selectedFundingJson.add(
        _inputJson(
          rawInput,
          transactionId: txid,
          index: index,
          signatureScript: Uint8List(66),
          computeBudget: 10,
          covenantId: null,
        ),
      );
      final totalInput = covInputsValue +
          selectedFunding.fold<BigInt>(
            BigInt.zero,
            (sum, input) => sum + input.utxoEntry.amount,
          );
      final candidateOutputs = [...outputJson];
      final inputJson = [...covInputJson, ...selectedFundingJson];
      candidateOutputs.add({
        'value': '0',
        'scriptPublicKey': {
          'version': changeScript.version,
          'script': kaspa.bytesToHex(changeScript.scriptPublicKey),
        },
      });
      final estimatedFee = _estimateNativeFee(
        inputJson,
        candidateOutputs,
        feeRate,
      );
      final availableChange = totalInput - covenantOutputValue - estimatedFee;
      if (availableChange < BigInt.zero) continue;
      final hasChange = availableChange >= BigInt.from(_kronDust);
      final actualChange = hasChange ? availableChange : BigInt.zero;
      final networkFee = totalInput - covenantOutputValue - actualChange;
      if (networkFee < estimatedFee ||
          networkFee > BigInt.from(100) * BigInt.from(100000000)) {
        continue;
      }
      if (hasChange) {
        outputs.add(
          kaspa.RawOutput(
            value: actualChange,
            scriptPublicKey: changeScript,
          ),
        );
        outputJson.add({
          'value': actualChange.toString(),
          'scriptPublicKey': {
            'version': changeScript.version,
            'script': kaspa.bytesToHex(changeScript.scriptPublicKey),
          },
        });
      }
      final transaction = kaspa.RawTransaction(
        version: 1,
        inputs: [...covenantInputs, ...selectedFunding],
        outputs: outputs,
        lockTime: BigInt.zero,
        subnetworkId: Uint8List(20),
        gas: BigInt.zero,
        payload: Uint8List(0),
      );
      final signInputs = [
        for (var index = covenantInputs.length;
            index < transaction.inputs.length;
            index++)
          {'index': index, 'sighashType': 1},
      ];
      if (signInputs.isEmpty) {
        throw const FormatException('Transaksi KRON tidak memiliki input wallet.');
      }
      final updatedQuote = KronNativeTradeQuote(
        operation: quote.operation,
        market: quote.market,
        ticker: quote.ticker,
        tokenName: quote.tokenName,
        inputAmount: quote.inputAmount,
        inputUnit: quote.inputUnit,
        outputAmount: quote.outputAmount,
        outputUnit: quote.outputUnit,
        protocolFee: quote.protocolFee,
        networkFee: networkFee,
        totalKas: quote.totalKas + networkFee,
      );
      return KronNativeBuiltTrade(
        txJsonString: jsonEncode(serializeKronNativeTransaction(transaction)),
        signInputs: signInputs,
        quote: updatedQuote,
      );
    }
    throw StateError('UTXO KAS tidak cukup untuk membayar transaksi dan biaya jaringan.');
  }

  static Uint8List materializeTokenScript(
    KronNativeTokenTemplate template,
    KronNativeTokenState state,
  ) {
    if (state.identifierType < 0 || state.identifierType > 3) {
      throw RangeError.range(state.identifierType, 0, 3, 'identifierType');
    }
    final start = template.stateStart;
    _expectLayout(
      template.script,
      start,
      const [(0, 32), (33, 1), (35, 8), (44, 1)],
      'KCC-20',
    );
    _require32(state.owner, 'KCC-20 owner');
    final out = Uint8List.fromList(template.script);
    out[start] = 32;
    out.setRange(start + 1, start + 33, state.owner);
    out[start + 33] = 1;
    out[start + 34] = state.identifierType;
    out[start + 35] = 8;
    out.setRange(start + 36, start + 44, _int8Le(state.amount));
    out[start + 44] = 1;
    out[start + 45] = state.isMinter ? 1 : 0;
    return out;
  }

  static Uint8List materializeCurveScript(
    KronNativeCurveTemplate template,
    Uint8List tokenCovid,
    BigInt tokenReserve,
  ) {
    _require32(tokenCovid, 'token covenant id');
    final start = template.stateStart;
    _expectLayout(template.script, start, const [(0, 1), (2, 32), (35, 8)], 'curve');
    final out = Uint8List.fromList(template.script);
    out[start] = 1;
    out[start + 1] = 0;
    out[start + 2] = 32;
    out.setRange(start + 3, start + 35, tokenCovid);
    out[start + 35] = 8;
    out.setRange(start + 36, start + 44, _int8Le(tokenReserve));
    return out;
  }

  static Uint8List materializePoolScript(
    KronNativePoolTemplate template,
    KronPoolState state,
    Uint8List tokenCovid,
    BigInt totalShares,
    Uint8List lpCovid,
  ) {
    _require32(tokenCovid, 'pool token covenant id');
    _require32(lpCovid, 'LP covenant id');
    final start = template.stateStart;
    _expectLayout(
      template.script,
      start,
      const [(0, 8), (9, 8), (18, 32), (51, 8), (60, 32)],
      'pool',
    );
    final out = Uint8List.fromList(template.script);
    out[start] = 8;
    out.setRange(start + 1, start + 9, _int8Le(state.kasReserve));
    out[start + 9] = 8;
    out.setRange(start + 10, start + 18, _int8Le(state.tokenReserve));
    out[start + 18] = 32;
    out.setRange(start + 19, start + 51, tokenCovid);
    out[start + 51] = 8;
    out.setRange(start + 52, start + 60, _int8Le(totalShares));
    out[start + 60] = 32;
    out.setRange(start + 61, start + 93, lpCovid);
    return out;
  }

  static KronNativeTokenState decodeTokenScript(Uint8List script) {
    const stateLength = 46;
    final offsets = <int>[];
    for (var start = 0; start + stateLength <= script.length; start++) {
      if (script[start] == 32 &&
          script[start + 33] == 1 &&
          script[start + 34] <= 3 &&
          script[start + 35] == 8 &&
          script[start + 44] == 1 &&
          script[start + 45] <= 1) {
        offsets.add(start);
      }
    }
    if (offsets.length != 1) {
      throw FormatException(
        'Script KCC-20 tidak memiliki state yang unik (${offsets.length} ditemukan).',
      );
    }
    final start = offsets.single;
    return KronNativeTokenState(
      owner: Uint8List.sublistView(script, start + 1, start + 33),
      identifierType: script[start + 34],
      amount: _readInt8Le(script, start + 36),
      isMinter: script[start + 45] == 1,
    );
  }

  static kaspa.Address scriptHashAddress(Uint8List redeemScript) =>
      kaspa.Address.scriptHash(
        prefix: kaspa.AddressPrefix.kaspa,
        hash: kaspa.blake2bDigest(data: redeemScript),
      );

  static Uint8List payToScriptHash(Uint8List redeemScript) {
    final hash = kaspa.blake2bDigest(data: redeemScript);
    return Uint8List.fromList([0xaa, 32, ...hash, 0x87]);
  }

  static Uint8List payToPubKey(Uint8List publicKey) {
    _require32(publicKey, 'public key');
    return Uint8List.fromList([32, ...publicKey, 0xac]);
  }

  static KronNativeSpend curveBuy({
    required KronNativeCurveTemplate curveTemplate,
    required KronNativeTokenTemplate tokenTemplate,
    required KronNativeCurveUtxo curve,
    required KronNativeInventoryUtxo inventory,
    required Uint8List curveCovid,
    required Uint8List tokenCovid,
    required Uint8List buyerPublicKey,
    required int presenceWitnessIndex,
    required KronCurveBuyQuote quote,
  }) {
    if (quote.kasIn <= BigInt.zero ||
        quote.kasIn % BigInt.from(_kronScale) != BigInt.zero ||
        quote.tokenOut <= BigInt.zero ||
        quote.tokenOut >= inventory.amount ||
        presenceWitnessIndex < 2 ||
        inventory.amount != curve.tokenReserve ||
        curve.realKas + quote.kasIn > BigInt.from(900000000000000)) {
      throw const FormatException('Parameter beli curve KRON tidak valid.');
    }
    final newTokenReserve = inventory.amount - quote.tokenOut;
    final inventoryOut = KronNativeTokenState(
      owner: curveCovid,
      identifierType: 2,
      amount: newTokenReserve,
      isMinter: false,
    );
    final buyerOut = KronNativeTokenState(
      owner: buyerPublicKey,
      identifierType: 3,
      amount: quote.tokenOut,
      isMinter: false,
    );
    final curveRedeem = materializeCurveScript(
      curveTemplate,
      tokenCovid,
      curve.tokenReserve,
    );
    final nextCurveRedeem = materializeCurveScript(
      curveTemplate,
      tokenCovid,
      newTokenReserve,
    );
    final inventoryRedeem = materializeTokenScript(
      tokenTemplate,
      KronNativeTokenState(
        owner: curveCovid,
        identifierType: 2,
        amount: inventory.amount,
        isMinter: false,
      ),
    );
    final inventoryOutRedeem = materializeTokenScript(
      tokenTemplate,
      inventoryOut,
    );
    final buyerRedeem = materializeTokenScript(tokenTemplate, buyerOut);
    final curveSig = _SigScript()
      ..integer(quote.kasIn)
      ..integer(quote.tokenOut)
      ..state(inventoryOut)
      ..state(buyerOut);
    if (curveTemplate.recipientBound) {
      curveSig
        ..integer(BigInt.from(presenceWitnessIndex))
        ..data(buyerPublicKey);
    }
    curveSig
      ..integer(BigInt.one)
      ..data(curveRedeem);
    final inventorySig = _transferSig(
      inventoryRedeem,
      [inventoryOut, buyerOut],
      [0],
    );
    final outputs = <KronNativeCovOutput>[
      _boundOutput(
        curve.realKas + quote.kasIn,
        payToScriptHash(nextCurveRedeem),
        curveCovid,
        0,
      ),
      _boundOutput(
        _continuationValue(inventory.value),
        payToScriptHash(inventoryOutRedeem),
        tokenCovid,
        1,
      ),
      _boundOutput(
        BigInt.from(_kronDust),
        payToScriptHash(buyerRedeem),
        tokenCovid,
        1,
      ),
      _plainOutput(
        _padFee(quote.kasIn * curveTemplate.creatorFeeBps ~/ BigInt.from(10000)),
        payToPubKey(curveTemplate.creatorFeeOwner),
      ),
      _plainOutput(
        _padFee(quote.kasIn * curveTemplate.platformFeeBps ~/ BigInt.from(10000)),
        payToPubKey(curveTemplate.platformFeeOwner),
      ),
    ];
    if (curveTemplate.devFundOwner != null &&
        curveTemplate.devFundBps != null) {
      outputs.add(
        _plainOutput(
          _padFee(
            quote.kasIn *
                curveTemplate.devFundBps! ~/
                BigInt.from(10000),
          ),
          payToPubKey(curveTemplate.devFundOwner!),
        ),
      );
    }
    return KronNativeSpend(
      inputs: [
        KronNativeCovInput(
          transactionId: curve.transactionId,
          index: curve.index,
          value: curve.realKas,
          script: payToScriptHash(curveRedeem),
          signatureScript: curveSig.bytes,
          role: 'curve',
        ),
        KronNativeCovInput(
          transactionId: inventory.transactionId,
          index: inventory.index,
          value: inventory.value,
          script: payToScriptHash(inventoryRedeem),
          signatureScript: inventorySig,
          role: 'inventory',
        ),
      ],
      outputs: outputs,
    );
  }

  static KronNativeSpend curveSell({
    required KronNativeCurveTemplate curveTemplate,
    required KronNativeTokenTemplate tokenTemplate,
    required KronNativeCurveUtxo curve,
    required KronNativeInventoryUtxo inventory,
    required List<KronNativeTokenUtxo> sellerTokens,
    required Uint8List curveCovid,
    required Uint8List tokenCovid,
    required Uint8List sellerPublicKey,
    required int presenceWitnessIndex,
    required KronCurveSellQuote quote,
  }) {
    if (sellerTokens.isEmpty ||
        sellerTokens.length > 2 ||
        sellerTokens.length >= tokenTemplate.maxIns) {
      throw const FormatException('Curve KRON hanya menerima 1–2 input token penjual.');
    }
    final sellerAmount = sellerTokens.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + item.state.amount,
    );
    if (quote.tokenIn <= BigInt.zero ||
        quote.tokenIn > sellerAmount ||
        quote.kasOut <= BigInt.zero ||
        quote.kasOut % BigInt.from(_kronScale) != BigInt.zero ||
        quote.kasOut >= curve.realKas ||
        presenceWitnessIndex < 2 + sellerTokens.length ||
        inventory.amount != curve.tokenReserve) {
      throw const FormatException('Parameter jual curve KRON tidak valid.');
    }
    final change = sellerAmount - quote.tokenIn;
    final hasChange = change > BigInt.zero;
    final newTokenReserve = inventory.amount + quote.tokenIn;
    final inventoryOut = KronNativeTokenState(
      owner: curveCovid,
      identifierType: 2,
      amount: newTokenReserve,
      isMinter: false,
    );
    final traderChange = KronNativeTokenState(
      owner: sellerPublicKey,
      identifierType: 3,
      amount: hasChange ? change : BigInt.one,
      isMinter: false,
    );
    final curveRedeem = materializeCurveScript(
      curveTemplate,
      tokenCovid,
      curve.tokenReserve,
    );
    final nextCurveRedeem = materializeCurveScript(
      curveTemplate,
      tokenCovid,
      newTokenReserve,
    );
    final inventoryRedeem = materializeTokenScript(
      tokenTemplate,
      KronNativeTokenState(
        owner: curveCovid,
        identifierType: 2,
        amount: inventory.amount,
        isMinter: false,
      ),
    );
    final inventoryOutRedeem = materializeTokenScript(
      tokenTemplate,
      inventoryOut,
    );
    final transferStates = hasChange
        ? [inventoryOut, traderChange]
        : [inventoryOut];
    final curveSig = _SigScript()
      ..integer(quote.tokenIn)
      ..integer(quote.kasOut)
      ..state(inventoryOut)
      ..state(traderChange);
    if (curveTemplate.recipientBound) {
      curveSig
        ..integer(BigInt.from(presenceWitnessIndex))
        ..data(sellerPublicKey);
    }
    curveSig
      ..integer(BigInt.from(2))
      ..data(curveRedeem);
    final inputs = <KronNativeCovInput>[
      KronNativeCovInput(
        transactionId: curve.transactionId,
        index: curve.index,
        value: curve.realKas,
        script: payToScriptHash(curveRedeem),
        signatureScript: curveSig.bytes,
        role: 'curve',
      ),
      KronNativeCovInput(
        transactionId: inventory.transactionId,
        index: inventory.index,
        value: inventory.value,
        script: payToScriptHash(inventoryRedeem),
        signatureScript: _transferSig(inventoryRedeem, transferStates, [
          0,
          ...List<int>.filled(sellerTokens.length, 2 + sellerTokens.length),
        ]),
        role: 'inventory',
      ),
    ];
    for (final token in sellerTokens) {
      final redeem = materializeTokenScript(tokenTemplate, token.state);
      inputs.add(
        KronNativeCovInput(
          transactionId: token.transactionId,
          index: token.index,
          value: token.value,
          script: payToScriptHash(redeem),
          signatureScript: _transferSig(redeem, transferStates, [
            0,
            presenceWitnessIndex,
          ]),
          role: 'sellerToken',
        ),
      );
    }
    final outputs = <KronNativeCovOutput>[
      _boundOutput(
        curve.realKas - quote.kasOut,
        payToScriptHash(nextCurveRedeem),
        curveCovid,
        0,
      ),
      _boundOutput(
        _continuationValue(inventory.value),
        payToScriptHash(inventoryOutRedeem),
        tokenCovid,
        1,
      ),
      _plainOutput(
        _padFee(quote.kasOut * curveTemplate.creatorFeeBps ~/ BigInt.from(10000)),
        payToPubKey(curveTemplate.creatorFeeOwner),
      ),
      _plainOutput(
        _padFee(quote.kasOut * curveTemplate.platformFeeBps ~/ BigInt.from(10000)),
        payToPubKey(curveTemplate.platformFeeOwner),
      ),
    ];
    if (curveTemplate.devFundOwner != null &&
        curveTemplate.devFundBps != null) {
      outputs.add(
        _plainOutput(
          _padFee(
            quote.kasOut *
                curveTemplate.devFundBps! ~/
                BigInt.from(10000),
          ),
          payToPubKey(curveTemplate.devFundOwner!),
        ),
      );
    }
    if (hasChange) {
      outputs.add(
        _boundOutput(
          BigInt.from(_kronDust),
          payToScriptHash(materializeTokenScript(tokenTemplate, traderChange)),
          tokenCovid,
          1,
        ),
      );
    }
    return KronNativeSpend(inputs: inputs, outputs: outputs);
  }

  static KronNativeSpend poolBuy({
    required KronNativePoolTemplate poolTemplate,
    required KronNativeTokenTemplate tokenTemplate,
    required KronNativePoolUtxo pool,
    required KronNativePoolParams params,
    required List<KronNativeTokenUtxo> mergeTokens,
    required Uint8List tokenCovid,
    required Uint8List traderPublicKey,
    required int presenceWitnessIndex,
    required KronPoolBuyQuote quote,
  }) {
    if (mergeTokens.isNotEmpty) {
      throw const FormatException('Penggabungan token saat beli belum didukung.');
    }
    if (presenceWitnessIndex < 2) {
      throw const FormatException('Index witness buy pool tidak valid.');
    }
    final tokenState = KronNativeTokenState(
      owner: pool.poolCovid,
      identifierType: 2,
      amount: quote.newToken,
      isMinter: false,
    );
    final traderState = KronNativeTokenState(
      owner: traderPublicKey,
      identifierType: 3,
      amount: quote.tokenOut,
      isMinter: false,
    );
    final currentRedeem = materializePoolScript(
      poolTemplate,
      pool.state,
      tokenCovid,
      pool.state.totalShares,
      pool.lpCovid,
    );
    final nextRedeem = materializePoolScript(
      poolTemplate,
      KronPoolState(
        kasReserve: quote.newKas,
        tokenReserve: quote.newToken,
        totalShares: pool.state.totalShares,
      ),
      tokenCovid,
      pool.state.totalShares,
      pool.lpCovid,
    );
    final poolTokenInRedeem = materializeTokenScript(
      tokenTemplate,
      KronNativeTokenState(
        owner: pool.poolCovid,
        identifierType: 2,
        amount: pool.state.tokenReserve,
        isMinter: false,
      ),
    );
    final poolTokenOutRedeem = materializeTokenScript(tokenTemplate, tokenState);
    final traderRedeem = materializeTokenScript(tokenTemplate, traderState);
    final sig = _SigScript()
      ..integer(quote.kasIn ~/ BigInt.from(_kronScale))
      ..integer(quote.tokenOut)
      ..state(tokenState)
      ..state(traderState);
    if (poolTemplate.recipientBound) {
      sig
        ..integer(BigInt.from(presenceWitnessIndex))
        ..data(traderPublicKey);
    }
    sig
      ..integer(BigInt.zero)
      ..data(currentRedeem);
    return KronNativeSpend(
      inputs: [
        KronNativeCovInput(
          transactionId: pool.transactionId,
          index: pool.index,
          value: pool.state.kasReserve * BigInt.from(_kronScale),
          script: payToScriptHash(currentRedeem),
          signatureScript: sig.bytes,
          role: 'pool',
        ),
        KronNativeCovInput(
          transactionId: pool.tokenTransactionId,
          index: pool.tokenIndex,
          value: pool.tokenValue,
          script: payToScriptHash(poolTokenInRedeem),
          signatureScript: _transferSig(
            poolTokenInRedeem,
            [tokenState, traderState],
            [0],
          ),
          role: 'poolToken',
        ),
      ],
      outputs: [
        _boundOutput(
          quote.newKas * BigInt.from(_kronScale),
          payToScriptHash(nextRedeem),
          pool.poolCovid,
          0,
        ),
        _boundOutput(
          _continuationValue(pool.tokenValue),
          payToScriptHash(poolTokenOutRedeem),
          tokenCovid,
          1,
        ),
        _boundOutput(
          BigInt.from(_kronDust),
          payToScriptHash(traderRedeem),
          tokenCovid,
          1,
        ),
        _plainOutput(
          quote.creatorOut,
          payToPubKey(params.creatorFeeOwner),
        ),
        _plainOutput(
          quote.platformOut,
          payToPubKey(params.platformFeeOwner),
        ),
      ],
    );
  }

  static KronNativeSpend poolSell({
    required KronNativePoolTemplate poolTemplate,
    required KronNativeTokenTemplate tokenTemplate,
    required KronNativePoolUtxo pool,
    required KronNativePoolParams params,
    required List<KronNativeTokenUtxo> traderTokens,
    required Uint8List tokenCovid,
    required Uint8List traderPublicKey,
    required int presenceWitnessIndex,
    required KronPoolSellQuote quote,
  }) {
    if (traderTokens.isEmpty || traderTokens.length >= tokenTemplate.maxIns) {
      throw const FormatException('Input token jual pool KRON tidak valid.');
    }
    if (presenceWitnessIndex < 2 + traderTokens.length) {
      throw const FormatException('Index witness sell pool tidak valid.');
    }
    final totalTokenAmount = traderTokens.fold<BigInt>(
      BigInt.zero,
      (sum, token) => sum + token.state.amount,
    );
    final change = totalTokenAmount - quote.tokenIn;
    if (change < BigInt.zero) {
      throw const FormatException('Saldo token tidak cukup untuk transaksi jual.');
    }
    final hasChange = change > BigInt.zero;
    final poolTokenOut = KronNativeTokenState(
      owner: pool.poolCovid,
      identifierType: 2,
      amount: quote.newToken,
      isMinter: false,
    );
    final traderChangeOut = KronNativeTokenState(
      owner: traderPublicKey,
      identifierType: 3,
      amount: hasChange ? change : BigInt.one,
      isMinter: false,
    );
    final currentRedeem = materializePoolScript(
      poolTemplate,
      pool.state,
      tokenCovid,
      pool.state.totalShares,
      pool.lpCovid,
    );
    final nextRedeem = materializePoolScript(
      poolTemplate,
      KronPoolState(
        kasReserve: quote.newKas,
        tokenReserve: quote.newToken,
        totalShares: pool.state.totalShares,
      ),
      tokenCovid,
      pool.state.totalShares,
      pool.lpCovid,
    );
    final poolTokenInRedeem = materializeTokenScript(
      tokenTemplate,
      KronNativeTokenState(
        owner: pool.poolCovid,
        identifierType: 2,
        amount: pool.state.tokenReserve,
        isMinter: false,
      ),
    );
    final poolTokenOutRedeem = materializeTokenScript(
      tokenTemplate,
      poolTokenOut,
    );
    final changeRedeem = materializeTokenScript(
      tokenTemplate,
      traderChangeOut,
    );
    final states = hasChange ? [poolTokenOut, traderChangeOut] : [poolTokenOut];
    final sig = _SigScript()
      ..integer(quote.kasOutUnits)
      ..state(poolTokenOut)
      ..state(traderChangeOut);
    if (poolTemplate.recipientBound) {
      sig
        ..integer(BigInt.from(presenceWitnessIndex))
        ..data(traderPublicKey);
    }
    sig
      ..integer(BigInt.one)
      ..data(currentRedeem);
    final witness = 2 + traderTokens.length;
    final inputs = <KronNativeCovInput>[
      KronNativeCovInput(
        transactionId: pool.transactionId,
        index: pool.index,
        value: pool.state.kasReserve * BigInt.from(_kronScale),
        script: payToScriptHash(currentRedeem),
        signatureScript: sig.bytes,
        role: 'pool',
      ),
      KronNativeCovInput(
        transactionId: pool.tokenTransactionId,
        index: pool.tokenIndex,
        value: pool.tokenValue,
        script: payToScriptHash(poolTokenInRedeem),
        signatureScript: _transferSig(poolTokenInRedeem, states, [
          0,
          ...List<int>.filled(traderTokens.length, witness),
        ]),
        role: 'poolToken',
      ),
    ];
    for (final token in traderTokens) {
      final redeem = materializeTokenScript(tokenTemplate, token.state);
      inputs.add(
        KronNativeCovInput(
          transactionId: token.transactionId,
          index: token.index,
          value: token.value,
          script: payToScriptHash(redeem),
          signatureScript: _transferSig(redeem, states, [0, witness]),
          role: 'traderToken',
        ),
      );
    }
    final outputs = <KronNativeCovOutput>[
      _boundOutput(
        quote.newKas * BigInt.from(_kronScale),
        payToScriptHash(nextRedeem),
        pool.poolCovid,
        0,
      ),
      _boundOutput(
        _continuationValue(pool.tokenValue),
        payToScriptHash(poolTokenOutRedeem),
        tokenCovid,
        1,
      ),
      _plainOutput(
        quote.creatorOut,
        payToPubKey(params.creatorFeeOwner),
      ),
      _plainOutput(
        quote.platformOut,
        payToPubKey(params.platformFeeOwner),
      ),
    ];
    if (poolTemplate.recipientBound) {
      outputs.add(
        _plainOutput(
          quote.kasOut - quote.creatorFee - quote.platformFee,
          payToPubKey(traderPublicKey),
        ),
      );
    }
    if (hasChange) {
      outputs.add(
        _boundOutput(
          BigInt.from(_kronDust),
          payToScriptHash(changeRedeem),
          tokenCovid,
          1,
        ),
      );
    }
    return KronNativeSpend(inputs: inputs, outputs: outputs);
  }

  static Uint8List _transferSig(
    Uint8List redeem,
    List<KronNativeTokenState> states,
    List<int> witnesses,
  ) {
    if (states.isEmpty || witnesses.isEmpty) {
      throw const FormatException('Data signature KCC-20 tidak valid.');
    }
    final script = _SigScript();
    script.data(_concat(states.map((state) => state.owner).toList()));
    script.data(
      Uint8List.fromList(states.map((state) => state.identifierType).toList()),
    );
    script.data(
      _concat(states.map((state) => _int8Le(state.amount)).toList()),
    );
    script.data(
      Uint8List.fromList(
        states.map((state) => state.isMinter ? 1 : 0).toList(),
      ),
    );
    script
      ..data(Uint8List(0))
      ..data(Uint8List.fromList(witnesses))
      ..data(redeem);
    return script.bytes;
  }

  static KronNativeCovOutput _boundOutput(
    BigInt value,
    Uint8List script,
    Uint8List covenantId,
    int authorizingInput,
  ) => KronNativeCovOutput(
    value: value,
    script: script,
    covenantId: covenantId,
    authorizingInput: authorizingInput,
  );

  static KronNativeCovOutput _plainOutput(BigInt value, Uint8List script) =>
      KronNativeCovOutput(value: value, script: script);

  static BigInt _continuationValue(BigInt inputValue) {
    final dust = BigInt.from(_kronDust);
    return inputValue > dust ? inputValue : dust;
  }

  static BigInt _padFee(BigInt fee) {
    final minimum = BigInt.from(_kronFeeOutputMin);
    return fee > minimum ? fee : minimum;
  }

  static void _expectLayout(
    Uint8List script,
    int start,
    List<(int, int)> fields,
    String name,
  ) {
    for (final field in fields) {
      if (start < 0 ||
          start + field.$1 >= script.length ||
          script[start + field.$1] != field.$2) {
        throw FormatException('Layout state template $name tidak sesuai.');
      }
    }
  }
}

kaspa.RawInput _rawUtxo(Map<String, Object?> raw) {
  final scriptData = _map(raw['scriptPublicKey'], 'scriptPublicKey');
  final script = _hex(scriptData['script'], 'scriptPublicKey.script');
  final version = _integer(scriptData['version'], 'scriptPublicKey.version');
  if (version != 0) {
    throw const FormatException('Versi script UTXO KRON tidak didukung.');
  }
  final address = _addressForScript(script);
  final declaredAddress = raw['address'];
  if (declaredAddress is! String || declaredAddress != address.encoded) {
    throw const FormatException('Alamat UTXO tidak cocok dengan redeem script.');
  }
  final covenant = raw['covenantId'];
  return kaspa.RawInput(
    address: address,
    previousOutpoint: kaspa.Outpoint(
      transactionId: _string(
        _map(raw['outpoint'], 'outpoint')['transactionId'],
        'outpoint transactionId',
      ),
      index: _integer(_map(raw['outpoint'], 'outpoint')['index'], 'outpoint index'),
    ),
    signatureScript: Uint8List(0),
    sequence: BigInt.zero,
    sigOpCount: 0,
    computeBudget: 0,
    utxoEntry: kaspa.UtxoEntry(
      amount: _bigInt(raw['amount'], 'UTXO amount'),
      scriptPublicKey: kaspa.ScriptPublicKey(
        scriptPublicKey: script,
        version: version,
      ),
      blockDaaScore: _bigInt(raw['blockDaaScore'], 'UTXO blockDaaScore'),
      isCoinbase: raw['isCoinbase'] == true,
      covenantId: covenant == null
          ? null
          : _hex(covenant, 'UTXO covenantId'),
    ),
  );
}

Map<String, Object?> _inputJson(
  kaspa.RawInput input, {
  required String transactionId,
  required int index,
  required Uint8List signatureScript,
  required int computeBudget,
  required Uint8List? covenantId,
}) => {
  'transactionId': transactionId,
  'index': index,
  'signatureScript': kaspa.bytesToHex(signatureScript),
  'sequence': '0',
  'sigOpCount': 0,
  'computeBudget': computeBudget,
  'utxo': {
    'address': input.address.encoded,
    'amount': input.utxoEntry.amount.toString(),
    'scriptPublicKey': {
      'version': input.utxoEntry.scriptPublicKey.version,
      'script': kaspa.bytesToHex(
        input.utxoEntry.scriptPublicKey.scriptPublicKey,
      ),
    },
    'blockDaaScore': input.utxoEntry.blockDaaScore.toString(),
    'isCoinbase': input.utxoEntry.isCoinbase,
    'covenantId': covenantId == null
        ? null
        : kaspa.bytesToHex(covenantId),
  },
};

kaspa.RawOutput _rawOutput(KronNativeCovOutput output) =>
    kaspa.RawOutput(
      value: output.value,
      scriptPublicKey: kaspa.ScriptPublicKey(
        scriptPublicKey: output.script,
        version: 0,
      ),
      covenant: output.covenantId == null
          ? null
          : kaspa.CovenantBinding(
              authorizingInput: output.authorizingInput!,
              covenantId: output.covenantId!,
            ),
    );

Map<String, Object?> _outputJson(KronNativeCovOutput output) => {
  'value': output.value.toString(),
  'scriptPublicKey': {'version': 0, 'script': kaspa.bytesToHex(output.script)},
  if (output.covenantId != null)
    'covenant': {
      'authorizingInput': output.authorizingInput,
      'covenantId': kaspa.bytesToHex(output.covenantId!),
    },
};

BigInt _estimateNativeFee(
  List<Map<String, Object?>> inputs,
  List<Map<String, Object?>> outputs,
  double feeRate,
) {
  var serializedSize = 94;
  var computeMass = 2000;
  for (final input in inputs) {
    final signatureScript = input['signatureScript']! as String;
    final computeBudget = _integer(input['computeBudget'], 'computeBudget');
    serializedSize += 54 + signatureScript.length ~/ 2;
    computeMass += computeBudget * 100;
  }
  for (final output in outputs) {
    final spk = _map(output['scriptPublicKey'], 'output scriptPublicKey');
    final script = _hex(spk['script'], 'output script');
    serializedSize += 18 + script.length;
    if (output['covenant'] != null) serializedSize += 34;
  }
  final transientMass = BigInt.from(serializedSize * 2);
  final compute = BigInt.from(computeMass);
  final billable = compute > transientMass ? compute : transientMass;
  final rate = BigInt.from(feeRate.ceil() < 100 ? 100 : feeRate.ceil());
  final fee = billable * rate * BigInt.from(6) ~/ BigInt.from(5);
  return fee > BigInt.from(10000) ? fee : BigInt.from(10000);
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Field $field pada data KRON tidak valid.');
}

String _string(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Field $field pada data KRON tidak valid.');
}

int _integer(Object? value, String field) {
  if (value is int && value >= 0) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 0) return parsed;
  }
  throw FormatException('Field $field pada data KRON tidak valid.');
}

BigInt _bigInt(Object? value, String field) {
  if (value is BigInt && value >= BigInt.zero) return value;
  if (value is int && value >= 0) return BigInt.from(value);
  if (value is String) {
    final parsed = BigInt.tryParse(value);
    if (parsed != null && parsed >= BigInt.zero) return parsed;
  }
  throw FormatException('Field $field pada data KRON tidak valid.');
}

Uint8List _hex(Object? value, String field) {
  if (value is! String ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw FormatException('Field $field bukan hex valid.');
  }
  return Uint8List.fromList(kaspa.hexToBytes(value));
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

int _computeBudget(String role) => switch (role) {
  'curve' || 'pool' => 400,
  'buyerToken' || 'sellerToken' || 'traderToken' => 100,
  'inventory' || 'poolToken' => 100,
  _ => throw FormatException('Role input KRON tidak dikenal: $role'),
};

kaspa.Address _addressForScript(Uint8List script) {
  if (script.length == 34 && script.first == 32 && script.last == 0xac) {
    return kaspa.Address.publicKey(
      prefix: kaspa.AddressPrefix.kaspa,
      publicKey: Uint8List.sublistView(script, 1, 33),
    );
  }
  if (script.length == 35 &&
      script.first == 33 &&
      script.last == 0xab) {
    return kaspa.Address.pubKeyECDSA(
      prefix: kaspa.AddressPrefix.kaspa,
      publicKey: Uint8List.sublistView(script, 1, 34),
    );
  }
  if (script.length == 35 &&
      script.first == 0xaa &&
      script[1] == 32 &&
      script.last == 0x87) {
    return kaspa.Address.scriptHash(
      prefix: kaspa.AddressPrefix.kaspa,
      hash: Uint8List.sublistView(script, 2, 34),
    );
  }
  throw const FormatException('Jenis script UTXO KRON tidak didukung.');
}

Uint8List _int8Le(BigInt value) {
  if (value < BigInt.zero || value >= (BigInt.one << 64)) {
    throw ArgumentError.value(value, 'value', 'Di luar rentang uint64.');
  }
  final bytes = Uint8List(8);
  var remaining = value;
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = (remaining & BigInt.from(255)).toInt();
    remaining >>= 8;
  }
  return bytes;
}

BigInt _readInt8Le(Uint8List bytes, int start) {
  var value = BigInt.zero;
  for (var index = 7; index >= 0; index--) {
    value = (value << 8) | BigInt.from(bytes[start + index]);
  }
  return value;
}

Uint8List _concat(List<Uint8List> buffers) {
  final length = buffers.fold<int>(0, (sum, item) => sum + item.length);
  final result = Uint8List(length);
  var offset = 0;
  for (final buffer in buffers) {
    result.setRange(offset, offset + buffer.length, buffer);
    offset += buffer.length;
  }
  return result;
}

void _require32(Uint8List value, String name) {
  if (value.length != 32) {
    throw FormatException('$name harus berukuran 32 byte.');
  }
}

class _SigScript {
  final _parts = <Uint8List>[];

  Uint8List get bytes => _concat(_parts);

  void data(Uint8List value) => _parts.add(_pushData(value));

  void integer(BigInt value) {
    final encoded = _scriptNumber(value);
    if (value == BigInt.zero ||
        value == -BigInt.one ||
        (value >= BigInt.one && value <= BigInt.from(16))) {
      _parts.add(encoded);
    } else {
      data(encoded);
    }
  }

  void state(KronNativeTokenState state) {
    _require32(state.owner, 'KCC-20 owner');
    data(state.owner);
    data(Uint8List.fromList([state.identifierType]));
    integer(state.amount);
    integer(state.isMinter ? BigInt.one : BigInt.zero);
  }
}

Uint8List _pushData(Uint8List value) {
  if (value.isEmpty) return Uint8List.fromList([0]);
  if (value.length == 1 && value.single >= 1 && value.single <= 16) {
    return Uint8List.fromList([0x50 + value.single]);
  }
  if (value.length == 1 && value.single == 0x81) {
    return Uint8List.fromList([0x4f]);
  }
  final prefix = <int>[];
  if (value.length <= 75) {
    prefix.add(value.length);
  } else if (value.length <= 0xff) {
    prefix.addAll([0x4c, value.length]);
  } else if (value.length <= 0xffff) {
    prefix.addAll([0x4d, value.length & 0xff, value.length >> 8]);
  } else {
    prefix.addAll([
      0x4e,
      value.length & 0xff,
      (value.length >> 8) & 0xff,
      (value.length >> 16) & 0xff,
      (value.length >> 24) & 0xff,
    ]);
  }
  return Uint8List.fromList([...prefix, ...value]);
}

Uint8List _scriptNumber(BigInt value) {
  if (value == BigInt.zero) return Uint8List.fromList([0]);
  if (value >= BigInt.one && value <= BigInt.from(16)) {
    return Uint8List.fromList([0x50 + value.toInt()]);
  }
  if (value == -BigInt.one) return Uint8List.fromList([0x4f]);
  final negative = value < BigInt.zero;
  var absolute = negative ? -value : value;
  final bytes = <int>[];
  while (absolute > BigInt.zero) {
    bytes.add((absolute & BigInt.from(255)).toInt());
    absolute >>= 8;
  }
  if ((bytes.last & 0x80) != 0) {
    bytes.add(negative ? 0x80 : 0);
  } else if (negative) {
    bytes[bytes.length - 1] |= 0x80;
  }
  return Uint8List.fromList(bytes);
}

String kronNativeOutpointKey(String txid, int index) =>
    '${txid.toLowerCase()}:$index';

Map<String, Object?> serializeKronNativeTransaction(
  kaspa.RawTransaction transaction,
) {
  final output = <String, Object?>{
    'version': transaction.version,
    'inputs': [
      for (final input in transaction.inputs)
        {
          'transactionId': input.previousOutpoint.transactionId,
          'index': input.previousOutpoint.index,
          'signatureScript': kaspa.bytesToHex(input.signatureScript),
          'sequence': input.sequence.toString(),
          'sigOpCount': input.sigOpCount,
          'computeBudget': input.computeBudget,
          'utxo': {
            'address': input.address.encoded,
            'amount': input.utxoEntry.amount.toString(),
            'scriptPublicKey': {
              'version': input.utxoEntry.scriptPublicKey.version,
              'script': kaspa.bytesToHex(
                input.utxoEntry.scriptPublicKey.scriptPublicKey,
              ),
            },
            'blockDaaScore': input.utxoEntry.blockDaaScore.toString(),
            'isCoinbase': input.utxoEntry.isCoinbase,
            'covenantId': input.utxoEntry.covenantId == null
                ? null
                : kaspa.bytesToHex(input.utxoEntry.covenantId!),
          },
        },
    ],
    'outputs': [
      for (final item in transaction.outputs)
        {
          'value': item.value.toString(),
          'scriptPublicKey': {
            'version': item.scriptPublicKey.version,
            'script': kaspa.bytesToHex(item.scriptPublicKey.scriptPublicKey),
          },
          'covenant': item.covenant == null
              ? null
              : {
                  'authorizingInput': item.covenant!.authorizingInput,
                  'covenantId': kaspa.bytesToHex(item.covenant!.covenantId),
                },
        },
    ],
    'lockTime': transaction.lockTime.toString(),
    'subnetworkId': kaspa.bytesToHex(transaction.subnetworkId),
    'gas': transaction.gas.toString(),
    'payload': transaction.payload == null
        ? ''
        : kaspa.bytesToHex(transaction.payload!),
  };
  return output;
}
