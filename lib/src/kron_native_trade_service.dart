import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

import 'kaspa_wallet_core.dart';
import 'kron_data.dart';
import 'kron_native_transaction.dart';
import 'kron_trade_math.dart';

class KronNativeTradeService {
  KronNativeTradeService({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri _indexer = Uri.parse('https://idx.kron.technology/v1/kcc20');
  static final Uri _registry = Uri.parse(
    'https://api.kron.technology/api/registry/tokenlist',
  );
  static final Uri _templateEndpoint = Uri.parse(
    'https://api.kron.technology/api/native/cp-template',
  );
  static final Uri _sequencer = Uri.parse('https://seq.kron.technology');

  final http.Client _client;

  Future<KronNativeBuiltTrade> buildTrade({
    required KaspaWalletSession session,
    required KronMarketListing market,
    required bool buy,
    required BigInt amount,
  }) async {
    if (session.profile.networkId != 'mainnet' || amount <= BigInt.zero) {
      throw ArgumentError(
        'KRON mainnet dan jumlah perdagangan positif diperlukan.',
      );
    }
    final wallet = await session.tradeWalletInfo();
    final walletAddresses = _walletAddresses(wallet);
    final publicKey = _hex(wallet['publicKey'], 'publicKey');
    if (publicKey.length != 32) {
      throw const FormatException('Kunci publik wallet KRON tidak valid.');
    }
    final token = _one(
      await _indexerGet('/token/${Uri.encodeComponent(market.ticker)}'),
      'token',
    );
    if (_str(token['covenantId'], 'covenantId').toLowerCase() !=
            market.covenantId.toLowerCase() ||
        token['graduated'] != market.graduated) {
      throw StateError('State token KRON berubah; muat ulang market.');
    }
    final tokenCovid = _hex(token['covenantId'], 'token covenantId');
    final curveCovid = _hex(token['curveCovenantId'], 'curve covenantId');
    final tokenList = _obj(await _getJson(_registry), 'registry');
    if (tokenList['network'] != 'mainnet' || tokenList['tokens'] is! List) {
      throw const FormatException('Registry token KRON mainnet tidak valid.');
    }
    final verified = (tokenList['tokens'] as List)
        .map((entry) => _obj(entry, 'registry token'))
        .where(
          (entry) =>
              entry['covenantId'] is String &&
              (entry['covenantId'] as String).toLowerCase() ==
                  _str(token['covenantId'], 'covenantId').toLowerCase(),
        )
        .toList();
    if (verified.length != 1 ||
        verified.single['chainVerified'] != true ||
        _obj(
              verified.single['extensions'],
              'token extensions',
            )['chainVerified'] !=
            true) {
      throw const FormatException(
        'Token tidak terverifikasi di registry KRON.',
      );
    }
    final extensions = _obj(verified.single['extensions'], 'token extensions');
    final curveParams = _obj(extensions['curveParams'], 'curve parameters');
    final version = extensions['templateVersion'];
    final templateBody = <String, Object?>{
      ...curveParams,
      'tokenCovid': token['covenantId'],
    };
    if (version != null) templateBody['templateVersion'] = version;
    final templateResponse = await _postJson(_templateEndpoint, templateBody);
    final templates = _templates(templateResponse);
    final walletAddressSet = walletAddresses.toSet();
    final addresses = <String>{...walletAddresses};
    final selectedTokenInputs = buy
        ? const <KronNativeTokenUtxo>[]
        : await _selectWalletTokenInputs(
            market.ticker,
            walletAddressSet,
            publicKey,
            templates.token,
            amount,
            graduated: market.graduated,
          );
    addresses.addAll(
      selectedTokenInputs.map(
        (input) => KronNativeTransactionBuilder.scriptHashAddress(
          KronNativeTransactionBuilder.materializeTokenScript(
            templates.token,
            input.state,
          ),
        ).encoded,
      ),
    );

    final feeRate = await session.getTradeFeeRate();
    late final KronNativeSpend spend;
    late final KronNativeTradeQuote quoteDisplay;
    if (market.graduated) {
      final poolCovid = _hex(extensions['poolCovenantId'], 'pool covenantId');
      final head = _obj(
        await _sequencerGet('/head?pool=${Uri.encodeComponent(market.ticker)}'),
        'pool sequencer head',
      );
      if (_int(head['depth'], 'pool sequencer depth') != 0) {
        throw StateError(
          'Pool KRON sedang memiliki transaksi sequencer tertunda.',
        );
      }
      final headState = _obj(head['head'], 'pool sequencer state');
      final reserves = _obj(headState['reserves'], 'pool reserves');
      final lpCovid = _hex(reserves['lpCovid'], 'LP covenantId');
      final poolState = KronPoolState(
        kasReserve: _uint(reserves['kasReserve'], 'pool kasReserve'),
        tokenReserve: _uint(reserves['tokenReserve'], 'pool tokenReserve'),
        totalShares: _uint(reserves['totalShares'], 'pool totalShares'),
      );
      final poolParams = KronPoolParams(
        creatorFeeBps: _uint(
          extensions['dexCreatorFeeBps'] ?? curveParams['dexCreatorFeeBps'],
          'pool creator fee',
        ),
        platformFeeBps: _uint(
          extensions['dexPlatformFeeBps'] ?? curveParams['dexPlatformFeeBps'],
          'pool platform fee',
        ),
        lpFeeBps: _uint(
          extensions['dexLpFeeBps'] ?? curveParams['dexLpFeeBps'],
          'pool LP fee',
        ),
        lockedShares: _uint(
          extensions['poolLockedShares'] ?? curveParams['poolLockedShares'],
          'locked LP shares',
        ),
      );
      final params = KronNativePoolParams(
        creatorFeeOwner: _hex(
          curveParams['creatorFeeOwner'],
          'creator fee owner',
        ),
        platformFeeOwner: _hex(
          curveParams['platformFeeOwner'],
          'platform fee owner',
        ),
        creatorFeeBps: poolParams.creatorFeeBps,
        platformFeeBps: poolParams.platformFeeBps,
        lpFeeBps: poolParams.lpFeeBps,
        lockedShares: poolParams.lockedShares,
      );
      final pool = KronNativePoolUtxo(
        transactionId: _point(headState['poolOutpoint'], 'pool outpoint').$1,
        index: _point(headState['poolOutpoint'], 'pool outpoint').$2,
        tokenTransactionId: _point(
          headState['poolTokenOutpoint'],
          'pool token outpoint',
        ).$1,
        tokenIndex: _point(
          headState['poolTokenOutpoint'],
          'pool token outpoint',
        ).$2,
        tokenValue: BigInt.zero,
        state: poolState,
        poolCovid: poolCovid,
        lpCovid: lpCovid,
      );
      final poolRedeem = KronNativeTransactionBuilder.materializePoolScript(
        templates.pool,
        poolState,
        tokenCovid,
        poolState.totalShares,
        lpCovid,
      );
      final poolTokenRedeem =
          KronNativeTransactionBuilder.materializeTokenScript(
            templates.token,
            KronNativeTokenState(
              owner: poolCovid,
              identifierType: 2,
              amount: poolState.tokenReserve,
              isMinter: false,
            ),
          );
      addresses
        ..add(
          KronNativeTransactionBuilder.scriptHashAddress(poolRedeem).encoded,
        )
        ..add(
          KronNativeTransactionBuilder.scriptHashAddress(
            poolTokenRedeem,
          ).encoded,
        );
      final utxos = await session.fetchTradeUtxos(addresses);
      _locateUtxo(
        utxos,
        pool.transactionId,
        pool.index,
        pool.state.kasReserve * BigInt.from(1000000),
        poolCovid,
        KronNativeTransactionBuilder.scriptHashAddress(poolRedeem).encoded,
      );
      final livePoolToken = _locateUtxo(
        utxos,
        pool.tokenTransactionId,
        pool.tokenIndex,
        null,
        tokenCovid,
        KronNativeTransactionBuilder.scriptHashAddress(poolTokenRedeem).encoded,
      );
      final actualPool = KronNativePoolUtxo(
        transactionId: pool.transactionId,
        index: pool.index,
        tokenTransactionId: pool.tokenTransactionId,
        tokenIndex: pool.tokenIndex,
        tokenValue: _uint(livePoolToken['amount'], 'pool token UTXO amount'),
        state: poolState,
        poolCovid: poolCovid,
        lpCovid: lpCovid,
      );
      final tokenInputs = _hydrateTokenInputs(selectedTokenInputs, utxos);
      if (buy) {
        final quote = quoteKronPoolBuy(poolState, poolParams, amount);
        if (quote == null) {
          throw StateError(
            'KRON tidak memberikan quote beli pool untuk jumlah ini.',
          );
        }
        spend = KronNativeTransactionBuilder.poolBuy(
          poolTemplate: templates.pool,
          tokenTemplate: templates.token,
          pool: actualPool,
          params: params,
          mergeTokens: const [],
          tokenCovid: tokenCovid,
          traderPublicKey: publicKey,
          presenceWitnessIndex: 2,
          quote: quote,
        );
        quoteDisplay = KronNativeTradeQuote(
          operation: 'buy',
          market: 'pool-v3',
          ticker: market.ticker,
          tokenName: market.name,
          inputAmount: quote.total,
          inputUnit: 'KAS',
          outputAmount: quote.tokenOut,
          outputUnit: market.ticker,
          protocolFee: quote.creatorOut + quote.platformOut,
          networkFee: BigInt.zero,
          totalKas: quote.total,
        );
      } else {
        final quote = quoteKronPoolSell(poolState, poolParams, amount);
        if (quote == null) {
          throw StateError(
            'KRON tidak memberikan quote jual pool untuk jumlah ini.',
          );
        }
        spend = KronNativeTransactionBuilder.poolSell(
          poolTemplate: templates.pool,
          tokenTemplate: templates.token,
          pool: actualPool,
          params: params,
          traderTokens: tokenInputs,
          tokenCovid: tokenCovid,
          traderPublicKey: publicKey,
          presenceWitnessIndex: 2 + tokenInputs.length,
          quote: quote,
        );
        quoteDisplay = KronNativeTradeQuote(
          operation: 'sell',
          market: 'pool-v3',
          ticker: market.ticker,
          tokenName: market.name,
          inputAmount: quote.tokenIn,
          inputUnit: market.ticker,
          outputAmount: quote.net,
          outputUnit: 'KAS',
          protocolFee: quote.creatorOut + quote.platformOut,
          networkFee: BigInt.zero,
          totalKas: quote.net,
        );
      }
      return _finishTrade(
        spend: spend,
        utxos: utxos,
        addresses: walletAddressSet.toList(),
        changeAddress: _str(wallet['changeAddress'], 'changeAddress'),
        feeRate: feeRate,
        quote: quoteDisplay,
      );
    } else {
      final head = _obj(
        await _sequencerGet(
          '/curve/head?covid=${Uri.encodeComponent(_str(token['curveCovenantId'], 'curveCovenantId'))}',
          allowConflict: true,
        ),
        'curve sequencer head',
      );
      if (head['ok'] != true ||
          _int(head['depth'], 'curve sequencer depth') != 0) {
        throw StateError(
          'Bonding curve KRON sedang sibuk atau sequencer menolak state.',
        );
      }
      final headState = head['head'] == null
          ? null
          : _obj(head['head'], 'curve sequencer state');
      final cpState = _obj(token['cpState'], 'curve state');
      final reserves = headState == null
          ? cpState
          : _obj(headState['reserves'], 'curve sequencer reserves');
      final curveState = KronCurveState(
        realKas: _uint(reserves['realKas'], 'curve realKas'),
        tokenReserve: _uint(reserves['tokenReserve'], 'curve tokenReserve'),
        vKas: _uint(curveParams['vKas'], 'curve virtual KAS'),
        graduationKas: _uint(
          curveParams['graduationKas'],
          'curve graduation threshold',
        ),
        creatorFeeBps: _uint(curveParams['creatorFeeBps'], 'curve creator fee'),
        platformFeeBps: _uint(
          curveParams['platformFeeBps'],
          'curve platform fee',
        ),
        devFundBps: curveParams['devFundBps'] == null
            ? null
            : _uint(curveParams['devFundBps'], 'curve dev fund fee'),
      );
      final curveRedeem = KronNativeTransactionBuilder.materializeCurveScript(
        templates.curve,
        tokenCovid,
        curveState.tokenReserve,
      );
      final inventoryRedeem =
          KronNativeTransactionBuilder.materializeTokenScript(
            templates.token,
            KronNativeTokenState(
              owner: curveCovid,
              identifierType: 2,
              amount: curveState.tokenReserve,
              isMinter: false,
            ),
          );
      final curveAddress = KronNativeTransactionBuilder.scriptHashAddress(
        curveRedeem,
      ).encoded;
      final inventoryAddress = KronNativeTransactionBuilder.scriptHashAddress(
        inventoryRedeem,
      ).encoded;
      addresses
        ..add(curveAddress)
        ..add(inventoryAddress);
      final utxos = await session.fetchTradeUtxos(addresses);
      final tokenInputs = _hydrateTokenInputs(selectedTokenInputs, utxos);
      final curvePoint = headState == null
          ? _findUniqueByState(
              utxos,
              curveAddress,
              curveState.realKas,
              _str(token['curveCovenantId'], 'curveCovenantId'),
              'curve',
            )
          : _point(headState['poolOutpoint'], 'curve outpoint');
      final inventoryPoint = headState == null
          ? _findUniqueByState(
              utxos,
              inventoryAddress,
              null,
              _str(token['covenantId'], 'covenantId'),
              'curve inventory',
            )
          : _point(headState['poolTokenOutpoint'], 'curve inventory outpoint');
      _locateUtxo(
        utxos,
        curvePoint.$1,
        curvePoint.$2,
        curveState.realKas,
        _hex(token['curveCovenantId'], 'curve covenantId'),
        curveAddress,
      );
      final liveInventory = _locateUtxo(
        utxos,
        inventoryPoint.$1,
        inventoryPoint.$2,
        null,
        tokenCovid,
        inventoryAddress,
      );
      final curve = KronNativeCurveUtxo(
        transactionId: curvePoint.$1,
        index: curvePoint.$2,
        realKas: curveState.realKas,
        tokenCovid: tokenCovid,
        tokenReserve: curveState.tokenReserve,
      );
      final inventory = KronNativeInventoryUtxo(
        transactionId: inventoryPoint.$1,
        index: inventoryPoint.$2,
        value: _uint(liveInventory['amount'], 'inventory UTXO amount'),
        amount: curveState.tokenReserve,
      );
      if (buy) {
        final quote = quoteKronCurveBuy(curveState, amount);
        if (quote == null) {
          throw StateError(
            'KRON tidak memberikan quote beli curve untuk jumlah ini.',
          );
        }
        spend = KronNativeTransactionBuilder.curveBuy(
          curveTemplate: templates.curve,
          tokenTemplate: templates.token,
          curve: curve,
          inventory: inventory,
          curveCovid: _hex(token['curveCovenantId'], 'curve covenantId'),
          tokenCovid: tokenCovid,
          buyerPublicKey: publicKey,
          presenceWitnessIndex: 2,
          quote: quote,
        );
        quoteDisplay = KronNativeTradeQuote(
          operation: 'buy',
          market: 'bonding-curve',
          ticker: market.ticker,
          tokenName: market.name,
          inputAmount: quote.total,
          inputUnit: 'KAS',
          outputAmount: quote.tokenOut,
          outputUnit: market.ticker,
          protocolFee: quote.fee,
          networkFee: BigInt.zero,
          totalKas: quote.total,
        );
      } else {
        final quote = quoteKronCurveSell(curveState, amount);
        if (quote == null) {
          throw StateError(
            'KRON tidak memberikan quote jual curve untuk jumlah ini.',
          );
        }
        spend = KronNativeTransactionBuilder.curveSell(
          curveTemplate: templates.curve,
          tokenTemplate: templates.token,
          curve: curve,
          inventory: inventory,
          sellerTokens: tokenInputs,
          curveCovid: _hex(token['curveCovenantId'], 'curve covenantId'),
          tokenCovid: tokenCovid,
          sellerPublicKey: publicKey,
          presenceWitnessIndex: 2 + tokenInputs.length,
          quote: quote,
        );
        quoteDisplay = KronNativeTradeQuote(
          operation: 'sell',
          market: 'bonding-curve',
          ticker: market.ticker,
          tokenName: market.name,
          inputAmount: quote.tokenIn,
          inputUnit: market.ticker,
          outputAmount: quote.net,
          outputUnit: 'KAS',
          protocolFee: quote.fee,
          networkFee: BigInt.zero,
          totalKas: quote.net,
        );
      }
      return _finishTrade(
        spend: spend,
        utxos: utxos,
        addresses: walletAddressSet.toList(),
        changeAddress: _str(wallet['changeAddress'], 'changeAddress'),
        feeRate: feeRate,
        quote: quoteDisplay,
      );
    }
  }

  Future<List<KronNativeTokenUtxo>> _selectWalletTokenInputs(
    String ticker,
    Set<String> walletAddresses,
    Uint8List walletPublicKey,
    KronNativeTokenTemplate template,
    BigInt amount, {
    required bool graduated,
  }) async {
    final pages = await Future.wait(
      walletAddresses.map(
        (address) => _indexerGet(
          '/token/${Uri.encodeComponent(ticker)}/address/${Uri.encodeComponent(address)}/utxos',
        ),
      ),
    );
    final candidates = <KronNativeTokenUtxo>[];
    for (final page in pages) {
      if (page is! List) {
        throw const FormatException(
          'Indexer KRON memberikan daftar UTXO token invalid.',
        );
      }
      for (final rawValue in page) {
        final raw = _obj(rawValue, 'token UTXO');
        final ownerAddress = _str(raw['ownerAddress'], 'token ownerAddress');
        if (!walletAddresses.contains(ownerAddress)) continue;
        final redeem = _hex(raw['redeemScriptHex'], 'token redeem script');
        final state = KronNativeTransactionBuilder.decodeTokenScript(redeem);
        if (state.identifierType != 3 ||
            !_same(state.owner, walletPublicKey) ||
            state.amount != _uint(raw['amount'], 'indexer token amount')) {
          continue;
        }
        final materialized =
            KronNativeTransactionBuilder.materializeTokenScript(
              template,
              state,
            );
        if (!_same(redeem, materialized)) {
          throw StateError(
            'Token UTXO tidak cocok dengan template KRON tersemat.',
          );
        }
        final point = _point(raw['outpoint'], 'token outpoint');
        candidates.add(
          KronNativeTokenUtxo(
            transactionId: point.$1,
            index: point.$2,
            value: BigInt.zero,
            state: state,
          ),
        );
      }
    }
    candidates.sort((a, b) => b.state.amount.compareTo(a.state.amount));
    final maximum = graduated ? template.maxIns - 1 : 2;
    final selected = <KronNativeTokenUtxo>[];
    var balance = BigInt.zero;
    for (final candidate in candidates) {
      if (selected.length >= maximum) break;
      selected.add(candidate);
      balance += candidate.state.amount;
      if (balance >= amount) break;
    }
    if (balance < amount) {
      throw StateError(
        'Saldo token KRON yang dapat dibelanjakan tidak mencukupi.',
      );
    }
    return List.unmodifiable(selected);
  }

  Future<KronNativeBuiltTrade> _finishTrade({
    required KronNativeSpend spend,
    required List<Map<String, Object?>> utxos,
    required List<String> addresses,
    required String changeAddress,
    required double feeRate,
    required KronNativeTradeQuote quote,
  }) async {
    return KronNativeTransactionBuilder.assemble(
      spend: spend,
      freshUtxos: utxos,
      walletAddresses: addresses,
      changeAddress: changeAddress,
      feeRate: feeRate,
      quote: quote,
    );
  }

  List<KronNativeTokenUtxo> _hydrateTokenInputs(
    List<KronNativeTokenUtxo> selected,
    List<Map<String, Object?>> utxos,
  ) {
    return List.unmodifiable([
      for (final token in selected)
        () {
          final matches = utxos.where((utxo) {
            final point = _obj(utxo['outpoint'], 'wallet token outpoint');
            return point['transactionId'] == token.transactionId &&
                _int(point['index'], 'wallet token index') == token.index;
          }).toList();
          if (matches.length != 1) {
            throw StateError(
              'UTXO token penjual sudah berubah; muat ulang token.',
            );
          }
          return KronNativeTokenUtxo(
            transactionId: token.transactionId,
            index: token.index,
            value: _uint(matches.single['amount'], 'wallet token UTXO value'),
            state: token.state,
          );
        }(),
    ]);
  }

  Future<dynamic> _indexerGet(String path) async {
    final body = await _getJson(Uri.parse('${_indexer.toString()}$path'));
    final result = _obj(body, 'indexer response');
    if (result['message'] != 'successful' || !result.containsKey('result')) {
      throw const FormatException('Indexer KRON tidak memberikan hasil valid.');
    }
    return result['result'];
  }

  Future<dynamic> _sequencerGet(
    String path, {
    bool allowConflict = false,
  }) async {
    final uri = Uri.parse(
      '${_sequencer.toString()}${path.startsWith('/') ? path : '/$path'}',
    );
    final response = await _requestWithRetry(
      uri,
      () => _client.get(uri, headers: const {'Accept': 'application/json'}),
      acceptedStatusCodes: allowConflict ? const {409} : const {},
    );
    if (response.statusCode != 200 &&
        !(allowConflict && response.statusCode == 409)) {
      throw KronHttpException(uri, response.statusCode);
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _getJson(Uri uri) async {
    final response = await _requestWithRetry(
      uri,
      () => _client.get(uri, headers: const {'Accept': 'application/json'}),
    );
    if (response.statusCode != 200) {
      throw KronHttpException(uri, response.statusCode);
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> body,
  ) async {
    final response = await _requestWithRetry(
      uri,
      () => _client.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'K-force/0.1.0 (native Flutter)',
        },
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode != 200) {
      throw KronHttpException(uri, response.statusCode);
    }
    return _obj(jsonDecode(response.body), 'template response');
  }

  Future<http.Response> _requestWithRetry(
    Uri uri,
    Future<http.Response> Function() request, {
    Set<int> acceptedStatusCodes = const {},
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await request().timeout(const Duration(seconds: 20));
        final retryable =
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (retryable && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        if (acceptedStatusCodes.contains(response.statusCode) ||
            response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        throw KronHttpException(uri, response.statusCode);
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } on KronHttpException catch (error) {
        if (error.statusCode == 408 ||
            error.statusCode == 429 ||
            error.statusCode >= 500) {
          lastError = error;
        } else {
          rethrow;
        }
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    throw StateError('Koneksi endpoint KRON gagal untuk $uri: $lastError');
  }

  void close() => _client.close();
}

class _NativeTemplates {
  const _NativeTemplates({
    required this.token,
    required this.curve,
    required this.pool,
  });

  final KronNativeTokenTemplate token;
  final KronNativeCurveTemplate curve;
  final KronNativePoolTemplate pool;
}

_NativeTemplates _templates(Map<String, Object?> response) {
  final token = _obj(response['token'], 'token template');
  final curve = _obj(response['curve'], 'curve template');
  final pool = _obj(response['pool'], 'pool template');
  final params = _obj(response['params'], 'template ABI parameters');
  for (final name in const [
    'tradeRecipientBound',
    'poolRecipientBound',
    'canonicalLpInventory',
    'zeroRemoveAllowed',
  ]) {
    if (!params.containsKey(name)) {
      throw FormatException('Template KRON tidak menyertakan ABI flag $name.');
    }
  }
  final curveParams = params;
  return _NativeTemplates(
    token: KronNativeTokenTemplate(
      script: _hex(token['scriptHex'], 'token template script'),
      stateStart: _int(token['stateStart'], 'token stateStart'),
      maxIns: _int(token['maxIns'], 'token maxIns'),
      maxOuts: _int(token['maxOuts'], 'token maxOuts'),
    ),
    curve: KronNativeCurveTemplate(
      script: _hex(curve['scriptHex'], 'curve template script'),
      stateStart: _int(curve['stateStart'], 'curve stateStart'),
      recipientBound: _boolFlag(curveParams['tradeRecipientBound']),
      creatorFeeOwner: _hex(curveParams['creatorFeeOwner'], 'creatorFeeOwner'),
      platformFeeOwner: _hex(
        curveParams['platformFeeOwner'],
        'platformFeeOwner',
      ),
      devFundOwner: curveParams['devFundOwner'] == null
          ? null
          : _hex(curveParams['devFundOwner'], 'devFundOwner'),
      creatorFeeBps: _uint(curveParams['creatorFeeBps'], 'curve creatorFeeBps'),
      platformFeeBps: _uint(
        curveParams['platformFeeBps'],
        'curve platformFeeBps',
      ),
      devFundBps: curveParams['devFundBps'] == null
          ? null
          : _uint(curveParams['devFundBps'], 'curve devFundBps'),
    ),
    pool: KronNativePoolTemplate(
      script: _hex(pool['scriptHex'], 'pool template script'),
      stateStart: _int(pool['stateStart'], 'pool stateStart'),
      recipientBound: _boolFlag(params['poolRecipientBound']),
    ),
  );
}

Map<String, Object?> _obj(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Data $label KRON tidak valid.');
}

dynamic _one(dynamic value, String label) {
  if (value is List) {
    if (value.length != 1) {
      throw FormatException('Indexer KRON harus mengembalikan satu $label.');
    }
    return value.single;
  }
  return value;
}

String _str(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Field $field KRON tidak valid.');
}

Uint8List _hex(Object? value, String field) {
  if (value is! String ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw FormatException('Field $field bukan hex valid.');
  }
  return Uint8List.fromList(kaspa.hexToBytes(value));
}

BigInt _uint(Object? value, String field) {
  if (value is int && value >= 0) return BigInt.from(value);
  if (value is BigInt && value >= BigInt.zero) return value;
  if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
    return BigInt.parse(value);
  }
  throw FormatException('Field $field bukan integer unsigned.');
}

int _int(Object? value, String field) {
  final result = _uint(value, field);
  if (result > BigInt.from(0x7fffffff)) {
    throw FormatException('Field $field berada di luar rentang.');
  }
  return result.toInt();
}

bool _boolFlag(Object? value) {
  if (value == true || value == 1 || value == '1') return true;
  if (value == false || value == 0 || value == '0') return false;
  throw const FormatException('Flag ABI template KRON tidak valid.');
}

(String, int) _point(Object? value, String field) {
  final point = _obj(value, field);
  final txid = _str(point['transactionId'], '$field transactionId');
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid)) {
    throw FormatException('$field transactionId bukan hash valid.');
  }
  return (txid, _int(point['index'], '$field index'));
}

Map<String, Object?> _locateUtxo(
  List<Map<String, Object?>> entries,
  String transactionId,
  int index,
  BigInt? amount,
  Uint8List covenantId,
  String address,
) {
  final matches = entries.where((entry) {
    final outpoint = _obj(entry['outpoint'], 'UTXO outpoint');
    final entryCovenant = entry['covenantId'];
    return outpoint['transactionId'] == transactionId &&
        _int(outpoint['index'], 'UTXO index') == index &&
        (amount == null || _uint(entry['amount'], 'UTXO amount') == amount) &&
        entry['address'] == address &&
        (entryCovenant == null ||
            _str(entryCovenant, 'UTXO covenantId').toLowerCase() ==
                kaspa.bytesToHex(covenantId).toLowerCase());
  }).toList();
  if (matches.length != 1) {
    throw StateError('UTXO state KRON tidak lagi cocok dengan sequencer head.');
  }
  return matches.single;
}

(String, int) _findUniqueByState(
  List<Map<String, Object?>> entries,
  String address,
  BigInt? amount,
  String covenantId,
  String label,
) {
  final matches = entries.where((entry) {
    final entryCovenant = entry['covenantId'];
    return entry['address'] == address &&
        (amount == null || _uint(entry['amount'], '$label amount') == amount) &&
        (entryCovenant == null ||
            _str(entryCovenant, '$label covenantId').toLowerCase() ==
                covenantId.toLowerCase());
  }).toList();
  if (matches.length != 1) {
    throw StateError('Tidak ada outpoint $label yang tunggal pada mainnet.');
  }
  return _point(matches.single['outpoint'], '$label outpoint');
}

List<String> _walletAddresses(Map<String, Object?> wallet) {
  final values = wallet['addresses'];
  if (values is! List) {
    throw const FormatException(
      'Alamat wallet untuk transaksi KRON tidak valid.',
    );
  }
  final addresses = <String>{};
  for (final item in values) {
    final address = _str(
      _obj(item, 'wallet address')['address'],
      'wallet address',
    );
    if (kaspa.Address.tryParse(
          address,
          expectedPrefix: kaspa.AddressPrefix.kaspa,
        ) ==
        null) {
      throw const FormatException('Wallet hanya mendukung alamat mainnet.');
    }
    addresses.add(address);
  }
  final receive = _str(wallet['receiveAddress'], 'receiveAddress');
  final change = _str(wallet['changeAddress'], 'changeAddress');
  if (!addresses.contains(receive) || !addresses.contains(change)) {
    throw const FormatException('Alamat receive/change tidak terverifikasi.');
  }
  return List.unmodifiable(addresses);
}

bool _same(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}
