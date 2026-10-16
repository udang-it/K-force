import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/k_force.dart';
import 'package:k_force/src/kron_data.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

void main() {
  test('node gRPC Kaspium dan indexer Kaspa merespons mainnet', () async {
    const profile = KaspaNetworkProfile.mainnet;
    kaspa.ServerInfo? serverInfo;
    String? connectedEndpoint;
    kaspa.RpcService? connectedRpc;

    for (final endpoint in profile.grpcEndpoints) {
      final rpc = kaspa.GrpcService.url(
        endpoint.target,
        tls: endpoint.tls,
        timeout: const Duration(seconds: 15),
      );
      try {
        await rpc.connect();
        final info = await rpc.getServerInfo();
        if (info.networkId == profile.networkId && info.hasUtxoIndex) {
          serverInfo = info;
          connectedEndpoint = endpoint.target;
          connectedRpc = rpc;
          break;
        }
      } catch (_) {
        await rpc.disconnect();
      }
    }

    expect(serverInfo, isNotNull);
    expect(connectedEndpoint, isNotNull);
    expect(serverInfo!.isSynced, isTrue);
    expect(serverInfo.hasUtxoIndex, isTrue);
    await connectedRpc!.disconnect();

    const recoveryPhrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final address = KaspaWalletCore.deriveAddressFromMnemonic(recoveryPhrase);
    final activity = await kaspa.ApiService.url(
      profile.indexerUrl,
    ).checkActive(addresses: [address]);

    expect(activity, hasLength(1));
    expect(activity.single.address, address);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('launchpad, market, registry, dan chart menerima data live KRON', () async {
    final repository = KronDiscoveryRepository();
    try {
      final results = await Future.wait([
        repository.fetchMarkets(KronMarketKind.curve),
        repository.fetchMarkets(KronMarketKind.pool),
        repository.fetchVerifiedTokens(),
        repository.fetchToken('KRON'),
        repository.fetchOhlc('KRON'),
        repository.fetchTrades('KRON'),
      ]);
      final launchpad = results[0] as List<KronMarketListing>;
      final market = results[1] as List<KronMarketListing>;
      final verifiedTokens = results[2] as List<KronVerifiedToken>;
      final kronToken = results[3] as KronMarketListing;
      final candles = results[4] as List<KronOhlc>;
      final trades = results[5] as List<KronTrade>;

      expect(launchpad, isNotEmpty);
      expect(market, isNotEmpty);
      expect(verifiedTokens, isNotEmpty);
      expect(kronToken.ticker, 'KRON');
      expect(candles, isNotEmpty);
      expect(trades, isNotEmpty);
    } finally {
      repository.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('portfolio membaca saldo KCC-20 melalui indexer KRON', () async {
    const recoveryPhrase =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final address = KaspaWalletCore.deriveAddressFromMnemonic(recoveryPhrase);
    final repository = KronDiscoveryRepository();
    try {
      final balances = await repository.fetchPortfolioBalances([address]);
      expect(balances, isA<List<KronTokenBalance>>());
    } finally {
      repository.close();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
