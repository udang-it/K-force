import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;
import 'package:kaspium_wallet/kaspa/rpc/grpc/messages.pb.dart'
    as kaspa_messages;
import 'package:kaspium_wallet/kaspa/rpc/grpc/rpc.pb.dart' as kaspa_rpc;

import 'kasdex_contract.dart';

class KaspaGrpcEndpoint {
  const KaspaGrpcEndpoint({
    required this.host,
    this.port = 443,
    this.tls = true,
  });

  final String host;
  final int port;
  final bool tls;

  String get target => '$host:$port';
}

class KaspaNetworkProfile {
  const KaspaNetworkProfile({
    required this.network,
    required this.networkId,
    required this.indexerUrl,
    required this.grpcEndpoints,
  });

  final kaspa.KaspaNetwork network;
  final String networkId;
  final String indexerUrl;
  final List<KaspaGrpcEndpoint> grpcEndpoints;

  static const mainnet = KaspaNetworkProfile(
    network: kaspa.KaspaNetwork.mainnet,
    networkId: 'mainnet',
    indexerUrl: 'https://api.kaspa.org',
    grpcEndpoints: [KaspaGrpcEndpoint(host: 'node.kaspium.io')],
  );
}

class WalletCreation {
  const WalletCreation({
    required this.recoveryPhrase,
    required this.firstReceiveAddress,
  });

  final String recoveryPhrase;
  final String firstReceiveAddress;
}

class KaspaWalletAddress {
  const KaspaWalletAddress({
    required this.value,
    required this.index,
    required this.isChange,
    required this.isActive,
  });

  final String value;
  final int index;
  final bool isChange;
  final bool isActive;
}

class KaspaWalletSnapshot {
  const KaspaWalletSnapshot({
    required this.balanceSompi,
    required this.addresses,
    required this.spendableUtxoCount,
    required this.serverInfo,
    required this.connectedEndpoint,
  });

  final BigInt balanceSompi;
  final List<KaspaWalletAddress> addresses;
  final int spendableUtxoCount;
  final kaspa.ServerInfo serverInfo;
  final String connectedEndpoint;
}

class KaspaWalletCore {
  KaspaWalletCore({required this.profile, FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final KaspaNetworkProfile profile;
  final FlutterSecureStorage _secureStorage;
  final Set<KaspaWalletSession> _sessions = {};

  String get _seedKey => 'kforce.seed.${profile.networkId}';
  String get _receiveIndexKey => 'kforce.receive-index.${profile.networkId}';

  Future<bool> get hasWallet async =>
      await _secureStorage.read(key: _seedKey) != null;

  String generateRecoveryPhrase() => kaspa.generateMnemonic(strength: 256);

  Future<WalletCreation> createWallet({String passphrase = ''}) async {
    final recoveryPhrase = generateRecoveryPhrase();
    final firstReceiveAddress = await importWallet(
      recoveryPhrase,
      passphrase: passphrase,
    );
    return WalletCreation(
      recoveryPhrase: recoveryPhrase,
      firstReceiveAddress: firstReceiveAddress,
    );
  }

  Future<String> importWallet(
    String recoveryPhrase, {
    String passphrase = '',
  }) async {
    final normalized = _normalizeMnemonic(recoveryPhrase);
    if (!kaspa.isValidMnemonic(normalized)) {
      throw const FormatException('Frasa pemulihan BIP39 tidak valid.');
    }
    if (await hasWallet) {
      throw StateError('Dompet sudah tersedia pada jaringan ini.');
    }

    final seed = Uint8List.fromList(
      kaspa.hexToBytes(
        kaspa.mnemonicToSeedHex(normalized, passphrase: passphrase),
      ),
    );
    try {
      final firstAddress = deriveAddressFromSeed(
        seed,
        network: profile.network,
      );
      await _secureStorage.write(key: _seedKey, value: kaspa.bytesToHex(seed));
      try {
        await _secureStorage.write(key: _receiveIndexKey, value: '1');
      } catch (_) {
        await _secureStorage.delete(key: _seedKey);
        rethrow;
      }
      return firstAddress;
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  Future<KaspaWalletSession> unlock() async {
    final storedSeed = await _secureStorage.read(key: _seedKey);
    if (storedSeed == null) {
      throw StateError('Dompet belum dibuat atau diimpor.');
    }

    final seed = Uint8List.fromList(kaspa.hexToBytes(storedSeed));
    if (seed.length != kaspa.kSeedSize) {
      seed.fillRange(0, seed.length, 0);
      throw StateError(
        'Data seed lokal tidak valid. Hapus lalu pulihkan dompet.',
      );
    }
    final session = KaspaWalletSession._(
      seed,
      _secureStorage,
      profile: profile,
    );
    _sessions.add(session);
    return session;
  }

  Future<void> deleteWallet() async {
    Object? closeError;
    for (final session in _sessions) {
      try {
        await session.close();
      } catch (error) {
        closeError ??= error;
      }
    }
    _sessions.clear();
    await _secureStorage.delete(key: _seedKey);
    await _secureStorage.delete(key: _receiveIndexKey);
    if (closeError != null) {
      throw StateError(
        'Sesi ditutup, tetapi koneksi node gagal ditutup: $closeError',
      );
    }
  }

  static String deriveAddressFromMnemonic(
    String recoveryPhrase, {
    kaspa.KaspaNetwork network = kaspa.KaspaNetwork.mainnet,
    int typeIndex = 0,
    int addressIndex = 0,
    String passphrase = '',
  }) {
    final normalized = _normalizeMnemonic(recoveryPhrase);
    if (!kaspa.isValidMnemonic(normalized)) {
      throw const FormatException('Frasa pemulihan BIP39 tidak valid.');
    }
    final seed = Uint8List.fromList(
      kaspa.hexToBytes(
        kaspa.mnemonicToSeedHex(normalized, passphrase: passphrase),
      ),
    );
    try {
      return deriveAddressFromSeed(
        seed,
        network: network,
        typeIndex: typeIndex,
        addressIndex: addressIndex,
      );
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  static String deriveAddressFromSeed(
    Uint8List seed, {
    required kaspa.KaspaNetwork network,
    int typeIndex = 0,
    int addressIndex = 0,
  }) {
    if (seed.length != kaspa.kSeedSize || typeIndex < 0 || addressIndex < 0) {
      throw ArgumentError('Seed atau indeks derivasi tidak valid.');
    }
    final hdPublicKey = kaspa.HdWallet.hdPublicKeyFromSeed(
      seed,
      networkType: kaspa.networkTypeForNetwork(network),
    );
    final walletView = kaspa.HdWalletViewSchnorr(hdPublicKey);
    return kaspa.Address.publicKey(
      prefix: kaspa.addressPrefixForNetwork(network),
      publicKey: walletView.derivePublicKey(
        typeIndex: typeIndex,
        index: addressIndex,
      ),
    ).encoded;
  }
}

class KaspaWalletSession {
  KaspaWalletSession._(this._seed, this._secureStorage, {required this.profile})
    : _api = kaspa.ApiService.url(profile.indexerUrl);

  static const int addressGapLimit = 20;
  static const int maxAddressIndex = 10000;
  static const int coinbaseMaturityDaaScore = 100;

  final KaspaNetworkProfile profile;
  final Uint8List _seed;
  final FlutterSecureStorage _secureStorage;
  final kaspa.ApiService _api;
  late final kaspa.HdWalletViewSchnorr _publicWallet =
      kaspa.HdWalletViewSchnorr(
        kaspa.HdWallet.hdPublicKeyFromSeed(
          _seed,
          networkType: kaspa.networkTypeForNetwork(profile.network),
        ),
      );
  kaspa.RpcService? _rpc;
  kaspa.ServerInfo? _serverInfo;
  String? _connectedEndpoint;
  Future<kaspa.ServerInfo>? _connectionAttempt;
  Future<void> _receiveAddressLock = Future<void>.value();
  bool _closed = false;

  String get connectedEndpoint =>
      _connectedEndpoint ?? (throw StateError('Node belum terhubung.'));

  String get _receiveIndexKey => 'kforce.receive-index.${profile.networkId}';

  int _nextReceiveIndex = 0;

  Future<kaspa.ServerInfo> connect() {
    _ensureOpen();
    if (_rpc != null && _serverInfo != null) {
      return Future.value(_serverInfo!);
    }
    return _connectionAttempt ??= _connect().whenComplete(() {
      _connectionAttempt = null;
    });
  }

  Future<kaspa.ServerInfo> _connect() async {
    if (profile.grpcEndpoints.isEmpty) {
      throw StateError(
        'Belum ada endpoint gRPC untuk ${profile.networkId}; tambahkan node publik tepercaya ke profil jaringan.',
      );
    }

    final failures = <String>[];
    for (final endpoint in profile.grpcEndpoints) {
      final candidate = kaspa.GrpcService.url(
        endpoint.target,
        tls: endpoint.tls,
        timeout: const Duration(seconds: 12),
      );
      try {
        await candidate.connect();
        final info = await candidate.getServerInfo();
        if (info.networkId != profile.networkId) {
          throw StateError(
            'Node ${endpoint.target} melayani ${info.networkId}, bukan ${profile.networkId}.',
          );
        }
        if (!info.hasUtxoIndex) {
          throw StateError(
            'Node ${endpoint.target} tidak menyediakan UTXO index.',
          );
        }
        if (!info.isSynced) {
          throw StateError('Node ${endpoint.target} belum tersinkronisasi.');
        }
        _rpc = candidate;
        _serverInfo = info;
        _connectedEndpoint = endpoint.target;
        return info;
      } catch (error) {
        failures.add('${endpoint.target}: $error');
        try {
          await candidate.disconnect();
        } catch (_) {
          // Keep trying configured endpoints; disconnect errors are secondary.
        }
      }
    }
    throw StateError('Semua node gRPC gagal: ${failures.join(' | ')}');
  }

  Future<KaspaWalletSnapshot> refresh() async {
    final discovery = await _discoverExternalAddresses();
    final changeAddress = _deriveAddress(typeIndex: 1, index: 0);
    final queriedAddresses = <String>{
      ...discovery.addresses.map((address) => address.value),
      changeAddress,
    }.toList(growable: false);

    final balances = await _withRpc(
      (rpc) => rpc.getBalancesByAddresses(queriedAddresses),
    );
    final utxos = await _withRpc(
      (rpc) => rpc.getUtxosByAddresses(queriedAddresses),
    );
    final serverInfo = await connect();
    final balance = balances.fold<BigInt>(
      BigInt.zero,
      (total, entry) => total + entry.balance,
    );
    final spendable = _spendableUtxos(utxos, serverInfo);
    final addresses = <KaspaWalletAddress>[
      ...discovery.addresses,
      KaspaWalletAddress(
        value: changeAddress,
        index: 0,
        isChange: true,
        isActive: false,
      ),
    ];

    return KaspaWalletSnapshot(
      balanceSompi: balance,
      addresses: List.unmodifiable(addresses),
      spendableUtxoCount: spendable.length,
      serverInfo: serverInfo,
      connectedEndpoint: connectedEndpoint,
    );
  }

  Future<List<Map<String, Object?>>> fetchTradeUtxos(
    Iterable<String> addresses,
  ) async {
    if (profile.networkId != 'mainnet') {
      throw StateError('UTXO KRON hanya dapat dibaca pada mainnet.');
    }
    final checkedAddresses = addresses.toSet();
    if (checkedAddresses.isEmpty || checkedAddresses.length > 100) {
      throw ArgumentError.value(
        checkedAddresses.length,
        'addresses',
        'Harus berisi 1–100 alamat.',
      );
    }
    final prefix = kaspa.addressPrefixForNetwork(profile.network);
    for (final address in checkedAddresses) {
      if (kaspa.Address.tryParse(address, expectedPrefix: prefix) == null) {
        throw const FormatException('Alamat UTXO KRON bukan alamat mainnet.');
      }
    }
    final utxos = await _withRpc(
      (rpc) => rpc.getUtxosByAddresses(checkedAddresses),
    );
    return List.unmodifiable(
      utxos.map((utxo) {
        final entry = utxo.utxoEntry;
        return <String, Object?>{
          'address': utxo.address,
          'outpoint': <String, Object?>{
            'transactionId': utxo.outpoint.transactionId,
            'index': utxo.outpoint.index,
          },
          'amount': entry.amount.toString(),
          'scriptPublicKey': <String, Object?>{
            'version': entry.scriptPublicKey.version,
            'script': kaspa.bytesToHex(entry.scriptPublicKey.scriptPublicKey),
          },
          'blockDaaScore': entry.blockDaaScore.toString(),
          'isCoinbase': entry.isCoinbase,
          'covenantId': entry.covenantId == null
              ? null
              : kaspa.bytesToHex(entry.covenantId!),
        };
      }),
    );
  }

  Future<Map<String, Object?>> tradeWalletInfo() async {
    _ensureOpen();
    if (profile.networkId != 'mainnet') {
      throw StateError('Transaksi KRON hanya diizinkan pada mainnet.');
    }
    await connect();
    final discovery = await _discoverExternalAddresses();
    final receiveAddress = _deriveAddress(typeIndex: 0, index: 0);
    final changeAddress = _deriveAddress(typeIndex: 1, index: 0);
    return {
      'receiveAddress': receiveAddress,
      'changeAddress': changeAddress,
      'publicKey': kaspa.bytesToHex(
        _publicWallet.derivePublicKey(typeIndex: 0, index: 0),
      ),
      'addresses': [
        ...discovery.addresses.map(
          (address) => {
            'address': address.value,
            'typeIndex': 0,
            'index': address.index,
          },
        ),
        {'address': changeAddress, 'typeIndex': 1, 'index': 0},
      ],
    };
  }

  Future<List<String>> signKasDexLaunch(
    Map<String, dynamic> prepared, {
    required Map<String, Object?> requested,
    required String address,
  }) async {
    _ensureOpen();
    if (profile.networkId != 'mainnet') {
      throw StateError('Launch KasDex hanya diizinkan pada mainnet.');
    }
    final publicKey = _derivePublicKey(typeIndex: 0, index: 0);
    final expectedAddress = _deriveAddress(typeIndex: 0, index: 0);
    if (address != expectedAddress) {
      throw const FormatException('Alamat launch bukan alamat wallet aktif.');
    }
    _verifyKasDexLaunchParameters(prepared, requested);

    final poolCovid = _kasDexHex(prepared['pool_covid'], 'pool_covid');
    final tokenCovid = _kasDexHex(prepared['tok_covid'], 'tok_covid');
    final lpCovid = _kasDexHex(prepared['lp_covid'], 'lp_covid');
    if (poolCovid.length != 32 ||
        tokenCovid.length != 32 ||
        lpCovid.length != 32 ||
        {
              kaspa.bytesToHex(poolCovid),
              kaspa.bytesToHex(tokenCovid),
              kaspa.bytesToHex(lpCovid),
            }.length !=
            3) {
      throw const FormatException('ID covenant launch KasDex tidak valid.');
    }

    final expectedScript = '20${kaspa.bytesToHex(publicKey)}ac';
    final seedKas = _kasDexBigInt(requested['seed_kas'], 'seed_kas');
    final transaction = _kasDexMap(prepared['tx'], 'launch transaction');
    final genesis = prepared['genesis'];
    if (genesis is! List || genesis.length != 3) {
      throw const FormatException('Transaksi genesis KasDex tidak lengkap.');
    }
    final sighashes = _kasDexList(prepared['sighashes'], 'sighashes');
    if (sighashes.length != 5) {
      throw const FormatException('Jumlah sighash launch KasDex tidak valid.');
    }

    final digests = <String>[];
    final genesisCovids = [poolCovid, lpCovid, tokenCovid];
    for (var index = 0; index < genesis.length; index++) {
      final parsed = _kasDexRawTransaction(genesis[index]);
      final tx = parsed.transaction;
      if (tx.version != 1 ||
          tx.inputs.length != 1 ||
          tx.outputs.length != 2 ||
          !parsed.traderSigns.single ||
          !_kasDexInputBelongsToWallet(
            tx.inputs.single,
            expectedAddress,
            expectedScript,
          )) {
        throw const FormatException('Transaksi genesis KasDex tidak aman.');
      }
      final covenantOutput = tx.outputs.first;
      final changeOutput = tx.outputs.last;
      final suppliedOutputs = _kasDexList(
        _kasDexMap(genesis[index], 'genesis transaction')['outputs'],
        'genesis outputs',
      );
      final suppliedChange = _kasDexMap(suppliedOutputs.last, 'genesis change');
      if (covenantOutput.value != BigInt.from(100000000) ||
          covenantOutput.scriptPublicKey.version != 0 ||
          covenantOutput.covenant == null ||
          kaspa.bytesToHex(covenantOutput.covenant!.covenantId) !=
              kaspa.bytesToHex(genesisCovids[index]) ||
          !_kasDexIsTraderOutput(suppliedChange, expectedScript) ||
          changeOutput.scriptPublicKey.version != 0 ||
          changeOutput.covenant != null) {
        throw const FormatException(
          'Output transaksi genesis KasDex tidak cocok.',
        );
      }
      _verifyKasDexFee(tx);
      final suppliedSighash = _kasDexHex(
        _kasDexList(prepared['sighashes'], 'sighashes')[index],
        'sighash',
      );
      final computedSighash = kaspa.getSchnorrSignatureHash(
        tx: tx,
        inputIndex: 0,
        hashType: kaspa.SigHashType.sigHashAll,
        reusedValues: kaspa.SigHashReusedValues(),
      );
      if (!_kasDexBytesEqual(suppliedSighash, computedSighash)) {
        throw const FormatException(
          'Sighash transaksi genesis KasDex tidak cocok.',
        );
      }
      digests.add(kaspa.bytesToHex(computedSighash));
    }

    final mainParsed = _kasDexRawTransaction(transaction);
    final mainTx = mainParsed.transaction;
    final mainTraderIndexes = [
      for (var index = 0; index < mainParsed.traderSigns.length; index++)
        if (mainParsed.traderSigns[index]) index,
    ];
    if (mainTx.version != 1 ||
        mainTraderIndexes.length != 2 ||
        !_kasDexHasExpectedLaunchOutputs(
          transaction,
          mainTx,
          expectedScript,
          seedKas,
          kaspa.bytesToHex(poolCovid),
          {
            kaspa.bytesToHex(poolCovid),
            kaspa.bytesToHex(tokenCovid),
            kaspa.bytesToHex(lpCovid),
          },
        )) {
      throw const FormatException('Transaksi launch KasDex tidak aman.');
    }
    for (final index in mainTraderIndexes) {
      if (!_kasDexInputBelongsToWallet(
        mainTx.inputs[index],
        expectedAddress,
        expectedScript,
      )) {
        throw const FormatException(
          'Transaksi launch meminta input di luar wallet.',
        );
      }
    }
    _verifyKasDexFee(mainTx);
    final reusedValues = kaspa.SigHashReusedValues();
    for (var index = 0; index < mainTraderIndexes.length; index++) {
      final inputIndex = mainTraderIndexes[index];
      final supplied = _kasDexHex(sighashes[index + 3], 'sighash');
      final computed = kaspa.getSchnorrSignatureHash(
        tx: mainTx,
        inputIndex: inputIndex,
        hashType: kaspa.SigHashType.sigHashAll,
        reusedValues: reusedValues,
      );
      if (!_kasDexBytesEqual(supplied, computed)) {
        throw const FormatException(
          'Sighash transaksi launch KasDex tidak cocok.',
        );
      }
      digests.add(kaspa.bytesToHex(computed));
    }

    final discovery = await _discoverExternalAddresses();
    final signer = _LocalSchnorrSigner(
      seed: _seed,
      addresses: [
        ...discovery.addresses.map((entry) => (0, entry.index, entry.value)),
        (1, 0, _deriveAddress(typeIndex: 1, index: 0)),
      ],
    );
    final signatures = <String>[];
    for (final digest in digests) {
      final signature = await signer.sign(
        _kasDexHex(digest, 'verified sighash'),
        kaspa.Address.tryParse(
              address,
              expectedPrefix: kaspa.AddressPrefix.kaspa,
            ) ??
            (throw const FormatException('Alamat wallet Kaspa tidak valid.')),
      );
      signatures.add(kaspa.bytesToHex(signature));
    }
    return List.unmodifiable(signatures);
  }

  Future<List<String>> signKasDexSwap(
    Map<String, dynamic> prepared, {
    required Map<String, dynamic> pool,
    required String direction,
    required BigInt amountIn,
    required BigInt minimumAmountOut,
    required String address,
    required List<Map<String, Object?>> tokenBranches,
  }) async {
    _ensureOpen();
    if (profile.networkId != 'mainnet' ||
        !{'kasForTok', 'tokForKas'}.contains(direction) ||
        amountIn <= BigInt.zero ||
        minimumAmountOut <= BigInt.zero ||
        address != _deriveAddress(typeIndex: 0, index: 0)) {
      throw ArgumentError('Parameter signing swap KasDex tidak valid.');
    }

    final poolId = _kasDexString(pool['id'], 'pool id').toLowerCase();
    final poolCovid = _kasDexHex(pool['pool_covid'], 'pool_covid');
    final tokenCovid = _kasDexHex(pool['tok_covid'], 'tok_covid');
    if (poolId != kaspa.bytesToHex(poolCovid) ||
        poolCovid.length != 32 ||
        tokenCovid.length != 32 ||
        prepared['pool'] != pool['id'] ||
        prepared['direction'] != direction ||
        _kasDexBigInt(prepared['amount_in'], 'amount_in') != amountIn ||
        _kasDexBigInt(prepared['amount_out'], 'amount_out') <
            minimumAmountOut) {
      throw const FormatException(
        'Swap KasDex tidak cocok dengan pool, arah, atau quote.',
      );
    }

    final parsed = _kasDexRawTransaction(prepared['tx']);
    final transaction = parsed.transaction;
    final traderIndexes = [
      for (var index = 0; index < parsed.traderSigns.length; index++)
        if (parsed.traderSigns[index]) index,
    ];
    final expectedTraderScript =
        '20${kaspa.bytesToHex(_derivePublicKey(typeIndex: 0, index: 0))}ac';
    final expectedSignatures = direction == 'kasForTok' ? 1 : 2;
    final rawSighashes = prepared['sighashes'];
    if (transaction.version != 1 ||
        traderIndexes.length != expectedSignatures ||
        rawSighashes is! List ||
        rawSighashes.length != expectedSignatures) {
      throw const FormatException('Transaksi swap KasDex tidak valid.');
    }

    final branchOutpoints = <String, BigInt>{};
    for (final branch in tokenBranches) {
      final transactionId = _kasDexString(
        branch['transactionId'],
        'token branch transactionId',
      );
      final index = _kasDexInt(branch['index'], 'token branch index');
      branchOutpoints['${transactionId.toLowerCase()}:$index'] = _kasDexBigInt(
        branch['amount'],
        'token branch amount',
      );
    }
    var walletTokenInputAmount = BigInt.zero;
    for (final index in traderIndexes) {
      final input = transaction.inputs[index];
      final covenantId = input.utxoEntry.covenantId;
      if (covenantId == null) {
        if (!_kasDexInputBelongsToWallet(
          input,
          address,
          expectedTraderScript,
        )) {
          throw const FormatException(
            'Swap KasDex meminta KAS dari luar wallet.',
          );
        }
      } else if (direction != 'tokForKas' ||
          kaspa.bytesToHex(covenantId) != kaspa.bytesToHex(tokenCovid) ||
          !_kasDexIsScriptHashInput(input)) {
        throw const FormatException(
          'Swap KasDex meminta covenant token yang tidak dimiliki.',
        );
      } else {
        final outpoint =
            '${input.previousOutpoint.transactionId.toLowerCase()}:'
            '${input.previousOutpoint.index}';
        final branchAmount = branchOutpoints[outpoint];
        if (branchAmount == null || branchAmount != input.utxoEntry.amount) {
          throw const FormatException(
            'Input token swap tidak tercatat pada saldo wallet KasDex.',
          );
        }
        walletTokenInputAmount += branchAmount;
      }
    }

    final transactionMap = _kasDexMap(prepared['tx'], 'swap transaction');
    final outputMaps = _kasDexList(
      transactionMap['outputs'],
      'swap outputs',
    ).map((entry) => _kasDexMap(entry, 'swap output')).toList();
    if (outputMaps.length != transaction.outputs.length) {
      throw const FormatException('Output transaksi swap KasDex tidak cocok.');
    }
    final poolOutputs = <int>[];
    final tokenOutputs = <int>[];
    var traderOutputCount = 0;
    final knownCovids = {
      kaspa.bytesToHex(poolCovid),
      kaspa.bytesToHex(tokenCovid),
    };
    for (var index = 0; index < outputMaps.length; index++) {
      final output = outputMaps[index];
      final rawOutput = transaction.outputs[index];
      if (_kasDexInt(output['index'], 'output index') != index ||
          _kasDexInt(output['spk_version'], 'spk_version') != 0) {
        throw const FormatException('Output swap KasDex tidak valid.');
      }
      final covenantValue = output['covenant_id'];
      if (output['to_trader'] == true) {
        if (covenantValue != null ||
            output['script_public_key_hex'] is! String ||
            (output['script_public_key_hex'] as String).toLowerCase() !=
                expectedTraderScript) {
          throw const FormatException(
            'Output KAS swap tidak kembali ke wallet.',
          );
        }
        traderOutputCount++;
        continue;
      }
      if (covenantValue is! String ||
          !knownCovids.contains(covenantValue.toLowerCase()) ||
          rawOutput.covenant == null ||
          kaspa.bytesToHex(rawOutput.covenant!.covenantId) !=
              covenantValue.toLowerCase()) {
        throw const FormatException(
          'Output swap KasDex mengarah ke covenant yang tidak dikenal.',
        );
      }
      if (covenantValue.toLowerCase() == poolId) {
        poolOutputs.add(index);
      } else {
        tokenOutputs.add(index);
      }
    }
    if (traderOutputCount == 0 || poolOutputs.length != 1) {
      throw const FormatException(
        'Swap harus melanjutkan pool dan mengembalikan KAS ke wallet.',
      );
    }
    final poolOutputIndex = poolOutputs.single;
    final poolOutputMap = outputMaps[poolOutputIndex];
    final poolOutput = transaction.outputs[poolOutputIndex];
    final poolAuthorizingInput = _kasDexInt(
      poolOutputMap['authorizing_input'],
      'pool authorizing_input',
    );
    if (poolAuthorizingInput >= transaction.inputs.length ||
        kaspa.bytesToHex(
              transaction.inputs[poolAuthorizingInput].utxoEntry.covenantId ??
                  Uint8List(0),
            ) !=
            poolId) {
      throw const FormatException(
        'Input pool swap KasDex tidak dapat diverifikasi.',
      );
    }
    final poolInputValue =
        transaction.inputs[poolAuthorizingInput].utxoEntry.amount;
    final expectedPublicKey = _derivePublicKey(typeIndex: 0, index: 0);
    final expectedTokenAmount = direction == 'kasForTok'
        ? _kasDexBigInt(prepared['amount_out'], 'amount_out')
        : walletTokenInputAmount - amountIn;
    if (expectedTokenAmount < BigInt.zero ||
        (expectedTokenAmount == BigInt.zero && tokenOutputs.isNotEmpty) ||
        (expectedTokenAmount > BigInt.zero && tokenOutputs.length != 1)) {
      throw const FormatException(
        'Output token swap KasDex tidak cocok dengan saldo wallet.',
      );
    }
    if (expectedTokenAmount > BigInt.zero) {
      final tokenOutputIndex = tokenOutputs.single;
      final tokenOutputMap = outputMaps[tokenOutputIndex];
      final expectedTokenScript = kasDexV5TokenBranchScript(
        ownerXOnlyPublicKey: expectedPublicKey,
        amount: expectedTokenAmount,
      );
      if ((tokenOutputMap['script_public_key_hex'] as String).toLowerCase() !=
              expectedTokenScript ||
          transaction.outputs[tokenOutputIndex].value !=
              BigInt.from(100000000)) {
        throw const FormatException(
          'Output token KasDex tidak dikirim ke branch wallet.',
        );
      }
    }
    if (direction == 'kasForTok') {
      final poolKasAdded = poolOutput.value - poolInputValue;
      if (poolKasAdded <= BigInt.zero || poolKasAdded > amountIn) {
        throw const FormatException('Jumlah KAS pool swap tidak cocok.');
      }
    } else if (poolInputValue - poolOutput.value < minimumAmountOut) {
      throw const FormatException(
        'Output KAS swap di bawah batas minimum yang disetujui.',
      );
    }
    _verifyKasDexFee(transaction);

    final sighashes = _kasDexList(rawSighashes, 'sighashes');
    final reusedValues = kaspa.SigHashReusedValues();
    final digests = <Uint8List>[];
    for (var index = 0; index < traderIndexes.length; index++) {
      final digest = kaspa.getSchnorrSignatureHash(
        tx: transaction,
        inputIndex: traderIndexes[index],
        hashType: kaspa.SigHashType.sigHashAll,
        reusedValues: reusedValues,
      );
      if (!_kasDexBytesEqual(_kasDexHex(sighashes[index], 'sighash'), digest)) {
        throw const FormatException(
          'Sighash swap KasDex tidak cocok dengan transaksi.',
        );
      }
      digests.add(digest);
    }

    final discovery = await _discoverExternalAddresses();
    final signer = _LocalSchnorrSigner(
      seed: _seed,
      addresses: [
        ...discovery.addresses.map((entry) => (0, entry.index, entry.value)),
        (1, 0, _deriveAddress(typeIndex: 1, index: 0)),
      ],
    );
    final signerAddress =
        kaspa.Address.tryParse(
          address,
          expectedPrefix: kaspa.AddressPrefix.kaspa,
        ) ??
        (throw const FormatException('Alamat wallet Kaspa tidak valid.'));
    return List.unmodifiable([
      for (final digest in digests)
        kaspa.bytesToHex(await signer.sign(digest, signerAddress)),
    ]);
  }

  Future<double> getTradeFeeRate() async {
    final feeEstimate = await _withRpc((rpc) => rpc.getFeeEstimate());
    final rate = feeEstimate.priorityBucket.feerate;
    if (!rate.isFinite || rate <= 0) {
      throw StateError('Node memberikan estimasi biaya transaksi tidak valid.');
    }
    return rate;
  }

  Future<String> receiveAddress() async {
    _ensureOpen();
    final previous = _receiveAddressLock;
    final completer = Completer<void>();
    _receiveAddressLock = completer.future;
    await previous;
    try {
      final persistedIndex = int.tryParse(
        await _secureStorage.read(key: _receiveIndexKey) ?? '',
      );
      if (persistedIndex == null || persistedIndex < 0) {
        throw StateError('Indeks alamat receive tersimpan tidak valid.');
      }
      final index = persistedIndex > _nextReceiveIndex
          ? persistedIndex
          : _nextReceiveIndex;
      if (index > maxAddressIndex) {
        throw StateError('Batas indeks alamat receive telah tercapai.');
      }
      await _secureStorage.write(key: _receiveIndexKey, value: '${index + 1}');
      _nextReceiveIndex = index + 1;
      return _deriveAddress(typeIndex: 0, index: index);
    } finally {
      completer.complete();
    }
  }

  Future<List<kaspa.ApiTransaction>> transactions({int limit = 50}) async {
    if (limit < 1 || limit > 500) {
      throw RangeError.range(limit, 1, 500, 'limit');
    }
    final discovery = await _discoverExternalAddresses();
    final historyAddresses = <String>{
      ...discovery.addresses
          .where((address) => address.isActive)
          .map((address) => address.value),
    };
    final changeAddress = _deriveAddress(typeIndex: 1, index: 0);
    final changeActivity = await _withApiRetry(
      () => _api.checkActive(addresses: [changeAddress]),
    );
    if (changeActivity.any((entry) => entry.active)) {
      historyAddresses.add(changeAddress);
    }

    final byId = <String, kaspa.ApiTransaction>{};
    for (final address in historyAddresses) {
      final page = await _withApiRetry(
        () => _api.getTxsPageForAddress(
          address,
          limit: limit,
          resolvePreviousOutpoints: kaspa.ResolvePreviousOutpoints.light,
        ),
      );
      for (final transaction in page.txs) {
        byId[transaction.transactionId] = transaction;
      }
    }
    final result = byId.values.toList()
      ..sort((left, right) => right.blockTime.compareTo(left.blockTime));
    return result.take(limit).toList(growable: false);
  }

  Future<String> send({
    required String destination,
    required BigInt amountSompi,
  }) async {
    if (amountSompi <= BigInt.zero) {
      throw ArgumentError.value(
        amountSompi,
        'amountSompi',
        'Harus lebih dari 0.',
      );
    }
    await connect();
    final prefix = kaspa.addressPrefixForNetwork(profile.network);
    final recipient = kaspa.Address.tryParse(
      destination,
      expectedPrefix: prefix,
    );
    if (recipient == null) {
      throw const FormatException('Alamat tujuan Kaspa tidak valid.');
    }

    final discovery = await _discoverExternalAddresses();
    final changeAddress = _deriveAddress(typeIndex: 1, index: 0);
    final queriedAddresses = <String>{
      ...discovery.addresses.map((address) => address.value),
      changeAddress,
    }.toList(growable: false);
    final allUtxos = await _withRpc(
      (rpc) => rpc.getUtxosByAddresses(queriedAddresses),
    );
    final serverInfo = await connect();
    final spendable = _spendableUtxos(allUtxos, serverInfo);
    if (spendable.isEmpty) {
      throw StateError('Tidak ada UTXO yang dapat dibelanjakan.');
    }

    final feeEstimate = await _withRpc((rpc) => rpc.getFeeEstimate());
    final feeRate = feeEstimate.priorityBucket.feerate.ceil();
    final change = kaspa.Address.decodeAddress(changeAddress, prefix);
    final signer = _LocalSchnorrSigner(
      seed: _seed,
      addresses: [
        ...discovery.addresses.map(
          (address) => (0, address.index, address.value),
        ),
        (1, 0, changeAddress),
      ],
    );
    final rpc = _rpc;
    if (rpc == null) {
      throw StateError('Koneksi node terputus sebelum transaksi disusun.');
    }
    final walletService = kaspa.WalletService(signer: signer, rpc: rpc);
    final sendTx = walletService.createSendTx(
      toAddress: recipient,
      amount: kaspa.Amount.raw(amountSompi),
      spendableUtxos: spendable,
      feeRate: feeRate,
      minFee: kaspa.Amount.raw(kaspa.kMinimumRelayTransactionFee),
      changeAddress: change,
    );
    try {
      return await walletService.sendTransaction(sendTx.tx);
    } catch (_) {
      await _discardRpc();
      rethrow;
    }
  }

  Future<String> signAndSubmitKronPskt({
    required String txJsonString,
    required List<Map<String, dynamic>> signInputs,
  }) async {
    _ensureOpen();
    final serverInfo = await connect();
    if (serverInfo.networkId != 'mainnet') {
      throw StateError('Transaksi KRON hanya diizinkan pada mainnet.');
    }
    if (signInputs.isEmpty) {
      throw ArgumentError.value(
        signInputs,
        'signInputs',
        'Tidak boleh kosong.',
      );
    }

    final txMap = _kronMap(jsonDecode(txJsonString), 'transaction');
    final inputMaps = _kronList(txMap['inputs'], 'inputs');
    final inputs = inputMaps.map(_kronInput).toList(growable: true);
    final outputs = _kronList(
      txMap['outputs'],
      'outputs',
    ).map(_kronOutput).toList(growable: false);
    final transaction = kaspa.RawTransaction(
      version: _kronInt(txMap['version'], 'version'),
      inputs: inputs,
      outputs: outputs,
      lockTime: _kronBigInt(txMap['lockTime'], 'lockTime'),
      subnetworkId: _kronHexBytes(txMap['subnetworkId'], 'subnetworkId'),
      gas: _kronBigInt(txMap['gas'], 'gas'),
      payload: _kronHexBytes(txMap['payload'] ?? '', 'payload'),
    );
    if (transaction.version != 1 ||
        inputs.isEmpty ||
        outputs.isEmpty ||
        transaction.fee < BigInt.zero ||
        transaction.fee > BigInt.from(100) * kaspa.kSompiPerKaspa) {
      throw const FormatException('Transaksi KRON melewati batas keamanan.');
    }
    final outpoints = <String>{};
    for (final input in inputs) {
      final outpoint =
          '${input.previousOutpoint.transactionId}:${input.previousOutpoint.index}';
      if (!outpoints.add(outpoint)) {
        throw const FormatException('Transaksi KRON memakai UTXO duplikat.');
      }
    }

    final discovery = await _discoverExternalAddresses();
    final changeAddress = _deriveAddress(typeIndex: 1, index: 0);
    final signer = _LocalSchnorrSigner(
      seed: _seed,
      addresses: [
        ...discovery.addresses.map(
          (address) => (0, address.index, address.value),
        ),
        (1, 0, changeAddress),
      ],
    );
    final walletInputIndexes = <int>{};
    for (var index = 0; index < inputs.length; index++) {
      if (await signer.canSignForAddress(inputs[index].address)) {
        walletInputIndexes.add(index);
      }
    }
    final seenIndexes = <int>{};
    final verifiedSignInputs = <({int index, kaspa.SigHashType hashType})>[];
    final reusedValues = kaspa.SigHashReusedValues();
    for (final signInput in signInputs) {
      final index = _kronInt(signInput['index'], 'sign input index');
      final hashType = kaspa.SigHashType.tryRaw(
        _kronInt(signInput['sighashType'], 'sighashType'),
      );
      if (index < 0 ||
          index >= inputs.length ||
          !seenIndexes.add(index) ||
          hashType == null) {
        throw const FormatException('Daftar input signing KRON tidak valid.');
      }
      verifiedSignInputs.add((index: index, hashType: hashType));
    }
    if (seenIndexes.length != walletInputIndexes.length ||
        !seenIndexes.containsAll(walletInputIndexes)) {
      throw const FormatException(
        'Semua input milik wallet harus tercantum untuk ditandatangani.',
      );
    }
    for (final signInput in verifiedSignInputs) {
      final index = signInput.index;
      final hashType = signInput.hashType;
      final input = inputs[index];
      if (!await signer.canSignForAddress(input.address)) {
        throw StateError('Transaksi meminta signature alamat di luar wallet.');
      }
      final digest = kaspa.getSchnorrSignatureHash(
        tx: transaction,
        inputIndex: index,
        hashType: hashType,
        reusedValues: reusedValues,
      );
      final signature = await signer.sign(digest, input.address);
      inputs[index] = input.copyWith(
        signatureScript: Uint8List.fromList([
          signature.length + 1,
          ...signature,
          hashType.raw,
        ]),
      );
    }

    final signedTransaction = transaction.copyWith(inputs: inputs);
    final rpc = _rpc;
    if (rpc is! kaspa.GrpcService) {
      throw StateError('Node wallet tidak mendukung submission gRPC.');
    }
    final message = kaspa_messages.KaspadRequest(
      id: _transactionRequestId(),
      submitTransactionRequest: kaspa_rpc.SubmitTransactionRequestMessage(
        transaction: _encodeKronTransaction(signedTransaction),
      ),
    );
    try {
      final response = await rpc.client.call(message);
      final result = response.submitTransactionResponse;
      if (result.hasError()) {
        throw kaspa.RpcException(result.error);
      }
      return result.transactionId;
    } catch (_) {
      await _discardRpc();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _seed.fillRange(0, _seed.length, 0);
    await _discardRpc();
  }

  Future<T> _withRpc<T>(Future<T> Function(kaspa.RpcService rpc) action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await connect();
        final rpc = _rpc;
        if (rpc == null) throw StateError('Node belum terhubung.');
        return await action(rpc).timeout(const Duration(seconds: 20));
      } catch (error) {
        lastError = error;
        await _discardRpc();
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }
    Error.throwWithStackTrace(
      StateError('Permintaan ke node gagal setelah reconnect: $lastError'),
      StackTrace.current,
    );
  }

  Future<T> _withApiRetry<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await action().timeout(const Duration(seconds: 20));
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
    }
    Error.throwWithStackTrace(
      StateError('Permintaan ke indexer Kaspa gagal setelah retry: $lastError'),
      StackTrace.current,
    );
  }

  Future<void> _discardRpc() async {
    final rpc = _rpc;
    _rpc = null;
    _serverInfo = null;
    _connectedEndpoint = null;
    if (rpc != null) {
      try {
        await rpc.disconnect();
      } catch (_) {
        // The failed connection is already unusable; reconnect owns recovery.
      }
    }
  }

  Future<_AddressDiscovery> _discoverExternalAddresses() async {
    final generated = <KaspaWalletAddress>[];
    final persistedNextIndex =
        int.tryParse(await _secureStorage.read(key: _receiveIndexKey) ?? '') ??
        0;
    if (persistedNextIndex < 0 || persistedNextIndex > maxAddressIndex + 1) {
      throw StateError('Indeks alamat receive tersimpan tidak valid.');
    }
    var nextIndex = 0;
    var gap = 0;
    var lastActiveIndex = -1;

    while (gap < addressGapLimit || nextIndex < persistedNextIndex) {
      if (nextIndex > maxAddressIndex) {
        throw StateError('Pemindaian alamat melewati batas keamanan.');
      }
      final gapNeeded = addressGapLimit - gap;
      final issuedNeeded = persistedNextIndex - nextIndex;
      final count = (gapNeeded > issuedNeeded ? gapNeeded : issuedNeeded)
          .clamp(1, 100)
          .toInt();
      final end = (nextIndex + count).clamp(0, maxAddressIndex + 1);
      final batch = [
        for (var index = nextIndex; index < end; index++)
          KaspaWalletAddress(
            value: _deriveAddress(typeIndex: 0, index: index),
            index: index,
            isChange: false,
            isActive: false,
          ),
      ];
      if (batch.isEmpty) break;

      final activity = await _withApiRetry(
        () =>
            _api.checkActive(addresses: batch.map((address) => address.value)),
      );
      final activeValues = {
        for (final entry in activity)
          if (entry.active) entry.address,
      };
      for (final address in batch) {
        final isActive = activeValues.contains(address.value);
        generated.add(
          KaspaWalletAddress(
            value: address.value,
            index: address.index,
            isChange: false,
            isActive: isActive,
          ),
        );
        if (isActive) {
          lastActiveIndex = address.index;
          gap = 0;
        } else {
          gap++;
        }
        if (gap >= addressGapLimit && generated.length >= persistedNextIndex) {
          break;
        }
      }
      nextIndex = generated.length;
    }

    return _AddressDiscovery(
      addresses: generated,
      nextReceiveIndex: lastActiveIndex + 1,
    );
  }

  List<kaspa.Utxo> _spendableUtxos(
    Iterable<kaspa.Utxo> utxos,
    kaspa.ServerInfo serverInfo,
  ) {
    final daaScore = BigInt.from(serverInfo.virtualDaaScore);
    return utxos
        .where((utxo) {
          if (!utxo.utxoEntry.isCoinbase) return true;
          return daaScore - utxo.utxoEntry.blockDaaScore >=
              BigInt.from(coinbaseMaturityDaaScore);
        })
        .toList(growable: false);
  }

  String _deriveAddress({required int typeIndex, required int index}) =>
      kaspa.Address.publicKey(
        prefix: kaspa.addressPrefixForNetwork(profile.network),
        publicKey: _derivePublicKey(typeIndex: typeIndex, index: index),
      ).encoded;

  Uint8List _derivePublicKey({required int typeIndex, required int index}) =>
      _publicWallet.derivePublicKey(typeIndex: typeIndex, index: index);

  void _ensureOpen() {
    if (_closed) throw StateError('Sesi wallet sudah dikunci.');
  }
}

class _AddressDiscovery {
  const _AddressDiscovery({
    required this.addresses,
    required this.nextReceiveIndex,
  });

  final List<KaspaWalletAddress> addresses;
  final int nextReceiveIndex;
}

({kaspa.RawTransaction transaction, List<bool> traderSigns})
_kasDexRawTransaction(Object? value) {
  final map = _kasDexMap(value, 'transaction');
  final inputMaps = _kasDexList(map['inputs'], 'transaction inputs')
      .map((entry) => _kasDexMap(entry, 'transaction input'))
      .toList(growable: false);
  final outputMaps = _kasDexList(map['outputs'], 'transaction outputs')
      .map((entry) => _kasDexMap(entry, 'transaction output'))
      .toList(growable: false);
  final inputs = <kaspa.RawInput>[];
  final traderSigns = <bool>[];
  final outpoints = <String>{};
  for (final input in inputMaps) {
    final outpoint = input['outpoint'];
    if (outpoint is! String) {
      throw const FormatException('Outpoint transaksi KasDex tidak valid.');
    }
    final separator = outpoint.lastIndexOf(':');
    if (separator <= 0) {
      throw const FormatException('Outpoint transaksi KasDex tidak valid.');
    }
    final transactionId = outpoint.substring(0, separator);
    final inputIndex = int.tryParse(outpoint.substring(separator + 1));
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(transactionId) ||
        inputIndex == null ||
        inputIndex < 0 ||
        inputIndex > 0xffffffff ||
        !outpoints.add('${transactionId.toLowerCase()}:$inputIndex')) {
      throw const FormatException('Outpoint transaksi KasDex tidak valid.');
    }
    final scriptVersion = _kasDexInt(
      input['utxo_spk_version'],
      'utxo_spk_version',
    );
    if (scriptVersion > 0xffff) {
      throw const FormatException('Versi script input KasDex tidak valid.');
    }
    final scriptBytes = _kasDexHex(input['utxo_spk_hex'], 'utxo_spk_hex');
    final covenantId = input['utxo_covenant_id'] == null
        ? null
        : _kasDexHex(input['utxo_covenant_id'], 'utxo_covenant_id');
    if (covenantId != null && covenantId.length != 32) {
      throw const FormatException('Covenant input KasDex tidak valid.');
    }
    final traderSignsInput = input['trader_signs'];
    if (traderSignsInput is! bool) {
      throw const FormatException('Penanda input KasDex tidak valid.');
    }
    inputs.add(
      kaspa.RawInput(
        address: _kronAddressFromScript(scriptBytes, scriptVersion),
        previousOutpoint: kaspa.Outpoint(
          transactionId: transactionId.toLowerCase(),
          index: inputIndex,
        ),
        signatureScript: Uint8List(0),
        sequence: _kasDexBigInt(input['sequence'], 'sequence'),
        sigOpCount: 0,
        computeBudget: 0,
        utxoEntry: kaspa.UtxoEntry(
          amount: _kasDexBigInt(input['utxo_amount'], 'utxo_amount'),
          scriptPublicKey: kaspa.ScriptPublicKey(
            scriptPublicKey: scriptBytes,
            version: scriptVersion,
          ),
          blockDaaScore: BigInt.zero,
          isCoinbase: false,
          covenantId: covenantId,
        ),
      ),
    );
    traderSigns.add(traderSignsInput);
  }

  final outputs = <kaspa.RawOutput>[];
  for (final output in outputMaps) {
    final scriptVersion = _kasDexInt(output['spk_version'], 'spk_version');
    if (scriptVersion > 0xffff) {
      throw const FormatException('Versi script output KasDex tidak valid.');
    }
    final scriptBytes = _kasDexHex(
      output['script_public_key_hex'],
      'script_public_key_hex',
    );
    final covenantId = output['covenant_id'] == null
        ? null
        : _kasDexHex(output['covenant_id'], 'covenant_id');
    final authorizingInput = _kasDexInt(
      output['authorizing_input'] ?? 0,
      'authorizing_input',
    );
    if ((covenantId != null && covenantId.length != 32) ||
        authorizingInput > 0xffff) {
      throw const FormatException('Covenant output KasDex tidak valid.');
    }
    outputs.add(
      kaspa.RawOutput(
        value: _kasDexBigInt(output['value'], 'output value'),
        scriptPublicKey: kaspa.ScriptPublicKey(
          scriptPublicKey: scriptBytes,
          version: scriptVersion,
        ),
        covenant: covenantId == null
            ? null
            : kaspa.CovenantBinding(
                authorizingInput: authorizingInput,
                covenantId: covenantId,
              ),
      ),
    );
  }

  final subnetworkId = _kasDexHex(
    map['subnetwork_id_hex'],
    'subnetwork_id_hex',
  );
  if (subnetworkId.length != 20) {
    throw const FormatException('Subnetwork KasDex tidak valid.');
  }
  final transaction = kaspa.RawTransaction(
    version: _kasDexInt(map['version'], 'version'),
    inputs: inputs,
    outputs: outputs,
    lockTime: _kasDexBigInt(map['lock_time'], 'lock_time'),
    subnetworkId: subnetworkId,
    gas: _kasDexBigInt(map['gas'], 'gas'),
    payload: _kasDexHex(map['payload_hex'] ?? '', 'payload_hex'),
  );
  if (inputs.isEmpty || outputs.isEmpty) {
    throw const FormatException('Transaksi KasDex kosong.');
  }
  return (transaction: transaction, traderSigns: traderSigns);
}

bool _kasDexHasExpectedLaunchOutputs(
  Map<String, dynamic> source,
  kaspa.RawTransaction transaction,
  String expectedScript,
  BigInt seedKas,
  String poolCovid,
  Set<String> allowedCovenants,
) {
  final outputs = _kasDexList(source['outputs'], 'launch outputs');
  if (outputs.length != transaction.outputs.length) return false;
  var poolOutputCount = 0;
  var traderOutputCount = 0;
  for (var index = 0; index < outputs.length; index++) {
    final output = _kasDexMap(outputs[index], 'launch output');
    final rawOutput = transaction.outputs[index];
    if (_kasDexInt(output['index'], 'output index') != index ||
        _kasDexInt(output['spk_version'], 'spk_version') != 0) {
      return false;
    }
    final covenant = output['covenant_id'];
    final script = output['script_public_key_hex'];
    final toTrader = output['to_trader'];
    if (toTrader == true) {
      if (covenant != null ||
          script is! String ||
          script.toLowerCase() != expectedScript) {
        return false;
      }
      traderOutputCount++;
      continue;
    }
    if (covenant is! String ||
        !allowedCovenants.contains(covenant.toLowerCase())) {
      if (index != outputs.length - 2 ||
          covenant != null ||
          rawOutput.value != BigInt.from(100000000) ||
          script is! String ||
          !RegExp(r'^aa20[0-9a-f]{64}87$').hasMatch(script.toLowerCase())) {
        return false;
      }
      continue;
    }
    if (rawOutput.covenant == null ||
        covenant.toLowerCase() !=
            _kasDexHexStringFromOutputCovenant(
              rawOutput.covenant!.covenantId,
            )) {
      return false;
    }
    if (covenant.toLowerCase() == poolCovid) {
      if (rawOutput.value != seedKas) return false;
      poolOutputCount++;
    } else if (rawOutput.value != BigInt.from(100000000)) {
      return false;
    }
  }
  return traderOutputCount > 0 && poolOutputCount == 1;
}

String? _kasDexHexStringFromOutputCovenant(Uint8List? covenantId) =>
    covenantId == null ? null : kaspa.bytesToHex(covenantId);

bool _kasDexIsTraderOutput(
  Map<String, dynamic> output,
  String expectedScript,
) =>
    output['to_trader'] == true &&
    output['covenant_id'] == null &&
    output['script_public_key_hex'] is String &&
    (output['script_public_key_hex'] as String).toLowerCase() == expectedScript;

bool _kasDexInputBelongsToWallet(
  kaspa.RawInput input,
  String expectedAddress,
  String expectedScript,
) =>
    input.address.encoded == expectedAddress &&
    kaspa.bytesToHex(input.utxoEntry.scriptPublicKey.scriptPublicKey) ==
        expectedScript &&
    input.utxoEntry.covenantId == null;

bool _kasDexIsScriptHashInput(kaspa.RawInput input) {
  final script = input.utxoEntry.scriptPublicKey.scriptPublicKey;
  return input.utxoEntry.scriptPublicKey.version == 0 &&
      script.length == 35 &&
      script[0] == 0xaa &&
      script[1] == 0x20 &&
      script.last == 0x87;
}

void _verifyKasDexFee(kaspa.RawTransaction transaction) {
  final fee = transaction.fee;
  if (fee < BigInt.zero || fee > BigInt.from(100000000)) {
    throw const FormatException('Biaya transaksi KasDex di luar batas aman.');
  }
}

void _verifyKasDexLaunchParameters(
  Map<String, dynamic> prepared,
  Map<String, Object?> requested,
) {
  final ticker = prepared['ticker'];
  final name = prepared['name'];
  if (ticker is! String ||
      name is! String ||
      name != requested['name'] ||
      ticker != requested['ticker'] ||
      _kasDexBigInt(prepared['supply'], 'supply') !=
          _kasDexBigInt(requested['supply'], 'supply') ||
      _kasDexBigInt(prepared['seed_tok'], 'seed_tok') !=
          _kasDexBigInt(requested['seed_tok'], 'seed_tok') ||
      _kasDexBigInt(prepared['seed_kas'], 'seed_kas') !=
          _kasDexBigInt(requested['seed_kas'], 'seed_kas') ||
      _kasDexInt(prepared['lock_days'], 'lock_days') !=
          _kasDexInt(requested['lock_days'], 'lock_days')) {
    throw const FormatException(
      'Parameter hasil prepare KasDex berbeda dari yang diminta.',
    );
  }
  if (prepared['launch_id'] is! String ||
      (prepared['launch_id'] as String).isEmpty) {
    throw const FormatException('ID launch KasDex tidak valid.');
  }
}

List<Object?> _kasDexList(Object? value, String field) {
  if (value is List) return value.cast<Object?>();
  throw FormatException('Field $field KasDex tidak valid.');
}

Map<String, dynamic> _kasDexMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Field $field KasDex tidak valid.');
}

int _kasDexInt(Object? value, String field) {
  final parsed = switch (value) {
    int() => value,
    String() => int.tryParse(value),
    _ => null,
  };
  if (parsed == null || parsed < 0 || parsed > 0xffffffff) {
    throw FormatException('Field $field KasDex tidak valid.');
  }
  return parsed;
}

BigInt _kasDexBigInt(Object? value, String field) {
  final parsed = switch (value) {
    int() => BigInt.from(value),
    String() => BigInt.tryParse(value),
    _ => null,
  };
  if (parsed == null ||
      parsed < BigInt.zero ||
      parsed > BigInt.parse('18446744073709551615')) {
    throw FormatException('Field $field KasDex tidak valid.');
  }
  return parsed;
}

Uint8List _kasDexHex(Object? value, String field) {
  if (value is! String ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw FormatException('Field $field KasDex tidak valid.');
  }
  return Uint8List.fromList(kaspa.hexToBytes(value));
}

bool _kasDexBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _LocalSchnorrSigner implements kaspa.SignerBase {
  _LocalSchnorrSigner({
    required Uint8List seed,
    required List<(int, int, String)> addresses,
  }) : _wallet = kaspa.HdWallet.forSeed(
         Uint8List.fromList(seed),
         type: kaspa.HdWalletType.schnorr,
       ),
       _addressIndexes = {
         for (final entry in addresses) entry.$3: (entry.$1, entry.$2),
       };

  final kaspa.HdWallet _wallet;
  final Map<String, (int, int)> _addressIndexes;

  @override
  Future<bool> canSignForAddress(kaspa.Address address) async =>
      _addressIndexes.containsKey(address.encoded);

  @override
  Future<Uint8List> sign(Uint8List data, kaspa.Address address) async {
    final derivation = _addressIndexes[address.encoded];
    if (derivation == null) {
      throw StateError('Tidak ada kunci lokal untuk alamat input.');
    }
    final keyPair = _wallet.deriveKeyPair(
      typeIndex: derivation.$1,
      index: derivation.$2,
    );
    try {
      return kaspa.signSchnorr(hash: data, privateKey: keyPair.privateKey);
    } finally {
      keyPair.privateKey.fillRange(0, keyPair.privateKey.length, 0);
    }
  }
}

kaspa.RawInput _kronInput(Object? value) {
  final input = _kronMap(value, 'transaction input');
  final utxo = _kronMap(input['utxo'], 'transaction input UTXO');
  final scriptPublicKey = _kronMap(
    utxo['scriptPublicKey'],
    'UTXO scriptPublicKey',
  );
  final script =
      scriptPublicKey['script'] ?? scriptPublicKey['scriptPublicKey'];
  if (script is! String) {
    throw const FormatException('Script UTXO transaksi KRON tidak valid.');
  }
  final scriptBytes = _kronHexBytes(script, 'UTXO script');
  final address = _kronAddressFromScript(
    scriptBytes,
    _kronInt(scriptPublicKey['version'], 'UTXO script version'),
  );
  final addressValue = utxo['address'];
  if (addressValue != null) {
    final declaredAddress = addressValue is String
        ? kaspa.Address.tryParse(
            addressValue,
            expectedPrefix: kaspa.AddressPrefix.kaspa,
          )
        : null;
    if (declaredAddress?.encoded != address.encoded) {
      throw const FormatException('Alamat UTXO tidak cocok dengan script.');
    }
  }
  final covenantId = utxo['covenantId'];
  return kaspa.RawInput(
    address: address,
    previousOutpoint: kaspa.Outpoint(
      transactionId: _kronString(input['transactionId'], 'transactionId'),
      index: _kronInt(input['index'], 'input index'),
    ),
    signatureScript: _kronHexBytes(input['signatureScript'], 'signatureScript'),
    sequence: _kronBigInt(input['sequence'], 'sequence'),
    sigOpCount: _kronInt(input['sigOpCount'], 'sigOpCount'),
    computeBudget: _kronInt(input['computeBudget'], 'computeBudget'),
    utxoEntry: kaspa.UtxoEntry(
      amount: _kronBigInt(utxo['amount'], 'UTXO amount'),
      scriptPublicKey: kaspa.ScriptPublicKey(
        scriptPublicKey: scriptBytes,
        version: _kronInt(scriptPublicKey['version'], 'UTXO script version'),
      ),
      blockDaaScore: _kronBigInt(utxo['blockDaaScore'], 'blockDaaScore'),
      isCoinbase: _kronBool(utxo['isCoinbase'], 'isCoinbase'),
      covenantId: covenantId == null
          ? null
          : _kronHexBytes(covenantId, 'UTXO covenantId'),
    ),
  );
}

kaspa.Address _kronAddressFromScript(Uint8List script, int version) {
  if (version != 0) {
    throw const FormatException('Versi script UTXO KRON tidak didukung.');
  }
  if (script.length == 34 && script.first == 32 && script.last == 172) {
    return kaspa.Address.publicKey(
      prefix: kaspa.AddressPrefix.kaspa,
      publicKey: Uint8List.sublistView(script, 1, 33),
    );
  }
  if (script.length == 35 && script.first == 33 && script.last == 171) {
    return kaspa.Address.pubKeyECDSA(
      prefix: kaspa.AddressPrefix.kaspa,
      publicKey: Uint8List.sublistView(script, 1, 34),
    );
  }
  if (script.length == 35 &&
      script[0] == 170 &&
      script[1] == 32 &&
      script.last == 135) {
    return kaspa.Address.scriptHash(
      prefix: kaspa.AddressPrefix.kaspa,
      hash: Uint8List.sublistView(script, 2, 34),
    );
  }
  throw const FormatException('Jenis script UTXO KRON tidak didukung.');
}

kaspa.RawOutput _kronOutput(Object? value) {
  final output = _kronMap(value, 'transaction output');
  final scriptPublicKey = _kronMap(
    output['scriptPublicKey'],
    'output scriptPublicKey',
  );
  final script =
      scriptPublicKey['script'] ?? scriptPublicKey['scriptPublicKey'];
  if (script is! String) {
    throw const FormatException('Script output KRON tidak valid.');
  }
  final binding = output['covenant'];
  final covenant = binding == null
      ? null
      : _kronMap(binding, 'output covenant binding');
  return kaspa.RawOutput(
    value: _kronBigInt(output['value'], 'output value'),
    scriptPublicKey: kaspa.ScriptPublicKey(
      scriptPublicKey: _kronHexBytes(script, 'output script'),
      version: _kronInt(scriptPublicKey['version'], 'output script version'),
    ),
    covenant: covenant == null
        ? null
        : kaspa.CovenantBinding(
            authorizingInput: _kronInt(
              covenant['authorizingInput'],
              'covenant authorizingInput',
            ),
            covenantId: _kronHexBytes(
              covenant['covenantId'],
              'covenant covenantId',
            ),
          ),
  );
}

kaspa_rpc.RpcTransaction _encodeKronTransaction(
  kaspa.RawTransaction transaction,
) => kaspa_rpc.RpcTransaction(
  version: transaction.version,
  inputs: transaction.inputs.map(
    (input) => kaspa_rpc.RpcTransactionInput(
      previousOutpoint: kaspa_rpc.RpcOutpoint(
        transactionId: input.previousOutpoint.transactionId,
        index: input.previousOutpoint.index,
      ),
      signatureScript: kaspa.bytesToHex(input.signatureScript),
      sequence: input.sequence.toInt64(),
      sigOpCount: input.sigOpCount,
      computeBudget: input.computeBudget,
    ),
  ),
  outputs: transaction.outputs.map(
    (output) => kaspa_rpc.RpcTransactionOutput(
      amount: output.value.toInt64(),
      scriptPublicKey: kaspa_rpc.RpcScriptPublicKey(
        version: output.scriptPublicKey.version,
        scriptPublicKey: kaspa.bytesToHex(
          output.scriptPublicKey.scriptPublicKey,
        ),
      ),
      covenant: output.covenant == null
          ? null
          : kaspa_rpc.RpcCovenantBinding(
              authorizingInput: output.covenant!.authorizingInput,
              covenantId: kaspa.bytesToHex(output.covenant!.covenantId),
            ),
    ),
  ),
  lockTime: transaction.lockTime.toInt64(),
  subnetworkId: kaspa.bytesToHex(transaction.subnetworkId),
  gas: transaction.gas.toInt64(),
  payload: transaction.payload == null
      ? ''
      : kaspa.bytesToHex(transaction.payload!),
);

Int64 _transactionRequestId() => Int64(DateTime.now().microsecondsSinceEpoch);

Map<String, dynamic> _kronMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

List<Object?> _kronList(Object? value, String field) {
  if (value is List) return value.cast<Object?>();
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

String _kronString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

int _kronInt(Object? value, String field) {
  if (value is int && value >= 0) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 0) return parsed;
  }
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

BigInt _kronBigInt(Object? value, String field) {
  if (value is int && value >= 0) return BigInt.from(value);
  if (value is String) {
    final parsed = BigInt.tryParse(value);
    if (parsed != null && parsed >= BigInt.zero) return parsed;
  }
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

bool _kronBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('Field $field pada transaksi KRON tidak valid.');
}

Uint8List _kronHexBytes(Object? value, String field) {
  if (value is! String ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw FormatException('Field $field pada transaksi KRON tidak valid.');
  }
  return Uint8List.fromList(kaspa.hexToBytes(value));
}

String _normalizeMnemonic(String mnemonic) =>
    mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

String _kasDexString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Field $field KasDex tidak valid.');
}
