import 'dart:async';

import 'package:flutter/material.dart';
import 'package:k_force/src/amount_format.dart';
import 'package:k_force/src/kasdex_l1.dart';
import 'package:k_force/src/kaspa_wallet_core.dart';
import 'package:k_force/src/kron_data.dart';
import 'package:k_force/src/kron_native_trade_service.dart';
import 'package:k_force/src/kron_trade_amount.dart';

const _ink = Color(0xFF1B1E3B);
const _green = Color(0xFF5156D8);
const _greenDark = Color(0xFF373BA8);
const _mint = Color(0xFFE9EAFF);
const _paper = Color(0xFFF7F7FC);
const _line = Color(0xFFE1E2EF);
const _muted = Color(0xFF6E7088);
const _red = Color(0xFFB64236);

class KForceNavigationBar extends StatelessWidget {
  const KForceNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
    height: 68,
    backgroundColor: Colors.white,
    indicatorColor: _mint,
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.pie_chart_outline_rounded),
        selectedIcon: Icon(Icons.pie_chart_rounded),
        label: 'Portofolio',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet_rounded),
        label: 'Wallet',
      ),
      NavigationDestination(
        icon: Icon(Icons.rocket_launch_outlined),
        selectedIcon: Icon(Icons.rocket_launch_rounded),
        label: 'Launchpad',
      ),
      NavigationDestination(
        icon: Icon(Icons.show_chart_rounded),
        selectedIcon: Icon(Icons.show_chart_rounded),
        label: 'Market',
      ),
    ],
  );
}

class KForceTabShell extends StatefulWidget {
  const KForceTabShell({
    required this.portfolioPage,
    required this.walletPage,
    required this.launchpadPage,
    required this.marketPage,
    super.key,
  });

  final Widget portfolioPage;
  final Widget walletPage;
  final Widget launchpadPage;
  final Widget marketPage;

  @override
  State<KForceTabShell> createState() => _KForceTabShellState();
}

class _KForceTabShellState extends State<KForceTabShell> {
  int _selectedIndex = 0;
  final Set<int> _visitedTabs = {0};

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        widget.portfolioPage,
        _visitedTabs.contains(1) ? widget.walletPage : const SizedBox.shrink(),
        _visitedTabs.contains(2)
            ? widget.launchpadPage
            : const SizedBox.shrink(),
        _visitedTabs.contains(3) ? widget.marketPage : const SizedBox.shrink(),
      ],
    ),
    bottomNavigationBar: KForceNavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() {
        _selectedIndex = index;
        _visitedTabs.add(index);
      }),
    ),
  );
}

class KronPortfolioScreen extends StatefulWidget {
  const KronPortfolioScreen({
    required this.balanceSompi,
    required this.addresses,
    required this.onRefreshWallet,
    super.key,
  });

  final BigInt? balanceSompi;
  final List<String> addresses;
  final Future<void> Function() onRefreshWallet;

  @override
  State<KronPortfolioScreen> createState() => _KronPortfolioScreenState();
}

class _KronPortfolioScreenState extends State<KronPortfolioScreen> {
  final KronDiscoveryRepository _repository = KronDiscoveryRepository();
  List<KronTokenBalance> _balances = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  @override
  void didUpdateWidget(covariant KronPortfolioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameAddresses(oldWidget.addresses, widget.addresses)) {
      _loadBalances();
    }
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.onRefreshWallet();
    if (mounted) await _loadBalances();
  }

  Future<void> _loadBalances() async {
    if (widget.addresses.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final balances = await _repository.fetchPortfolioBalances(
        widget.addresses,
      );
      if (!mounted) return;
      setState(() {
        _balances = balances;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Saldo KCC-20 dari KRON gagal dimuat: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    appBar: AppBar(
      title: const Text('Portofolio'),
      actions: [
        IconButton(
          tooltip: 'Perbarui portofolio',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: RefreshIndicator(
      color: _green,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const Text(
            'Kaspa mainnet',
            style: TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.balanceSompi == null
                ? 'Saldo KAS belum tersedia'
                : '${formatKasAmount(widget.balanceSompi!)} KAS',
            style: const TextStyle(
              color: _ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Token KRON',
            style: TextStyle(
              color: _ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            _KronError(message: _error!, onRetry: _loadBalances)
          else if (_loading && _balances.isEmpty)
            _LoadingMessage(
              label: widget.addresses.isEmpty
                  ? 'Menunggu alamat wallet tersinkron…'
                  : 'Memuat saldo KCC-20 dari KRON…',
            )
          else if (_balances.isEmpty)
            const _EmptyMessage(
              message: 'Tidak ada saldo KCC-20 pada alamat wallet ini.',
            )
          else
            for (final balance in _balances) _BalanceRow(balance: balance),
        ],
      ),
    ),
  );
}

class KronLaunchpadScreen extends StatefulWidget {
  const KronLaunchpadScreen({
    required this.session,
    required this.onTradeSubmitted,
    super.key,
  });

  final KaspaWalletSession session;
  final Future<void> Function() onTradeSubmitted;

  @override
  State<KronLaunchpadScreen> createState() => _KronLaunchpadScreenState();
}

class _KronLaunchpadScreenState extends State<KronLaunchpadScreen> {
  final KasDexL1Repository _repository = KasDexL1Repository();
  List<KasDexL1Pool> _pools = const [];
  bool _loading = true;
  bool _launching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPools();
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _loadPools() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pools = await _repository.fetchPools();
      if (!mounted) return;
      setState(() {
        _pools = pools;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Pool KasDex gagal dimuat: $error';
        _loading = false;
      });
    }
  }

  Future<void> _showLaunchForm() async {
    final request = await showDialog<_KasDexLaunchRequest>(
      context: context,
      builder: (context) => const _KasDexLaunchDialog(),
    );
    if (request == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi deploy mainnet'),
        content: Text(
          '${request.name} (${request.ticker}) akan dibuat di KasDex L1. '
          'Supply ${request.supply}, seed ${request.seedToken} token dan '
          '${formatKasAmount(request.seedKasSompi)} KAS; likuiditas awal '
          'dikunci selama ${request.lockDays} hari. K-force akan memverifikasi '
          'transaksi lalu menandatangani input wallet secara lokal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deploy token'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      final txid = await _repository.launchToken(
        session: widget.session,
        name: request.name,
        ticker: request.ticker,
        supply: request.supply,
        seedToken: request.seedToken,
        seedKasSompi: request.seedKasSompi,
        lockDays: request.lockDays,
      );
      await widget.onTradeSubmitted();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Token dikirim ke Kaspa mainnet: ${_shortTransactionId(txid)}',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      await _loadPools();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Deploy KasDex gagal: $error';
      });
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        title: const Text('Launchpad'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang pool KasDex',
            onPressed: _loading ? null : _loadPools,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: _loadPools,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
          children: [
            const _SectionHeading(
              title: 'KasDex L1 Launchpad',
              subtitle: 'Deploy token dan lihat pool pilot · Kaspa mainnet',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _launching ? null : _showLaunchForm,
              icon: _launching
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(_launching ? 'Menyiapkan deploy…' : 'Deploy token'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              _KronError(message: _error!, onRetry: _loadPools)
            else if (_loading && _pools.isEmpty)
              const _LoadingMessage(label: 'Memuat pool KasDex L1…')
            else if (_pools.isEmpty)
              const _EmptyMessage(message: 'Belum ada pool KasDex L1.')
            else
              for (final pool in _pools)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _mint,
                      foregroundColor: _greenDark,
                      child: const Icon(Icons.token_rounded),
                    ),
                    title: Text('${pool.name} (${pool.ticker})'),
                    subtitle: Text(
                      '${formatKasAmount(pool.reserveKasSompi)} KAS · '
                      '${pool.reserveToken} token · '
                      '${pool.synced ? 'tersinkron' : 'belum sinkron'}'
                      '${pool.retired ? ' · retired' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showPoolDetails(pool),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPoolDetails(KasDexL1Pool pool) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${pool.name} (${pool.ticker})',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text('KasDex pool ID: ${pool.id}'),
              Text('Supply: ${pool.supply} ${pool.ticker}'),
              Text('Cadangan: ${formatKasAmount(pool.reserveKasSompi)} KAS'),
              Text('Token pool: ${pool.reserveToken} ${pool.ticker}'),
              Text(
                pool.synced
                    ? 'Status mainnet: tersinkron'
                    : 'Status mainnet: belum sinkron',
              ),
              if (pool.retired)
                const Text(
                  'Pool ini sudah retired dan tidak dapat diperdagangkan.',
                ),
              const SizedBox(height: 10),
              const Text(
                'Pembuatan token dikirim melalui API launch KasDex. '
                'Transaksi swap belum tersedia pada tampilan ini.',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KasDexLaunchRequest {
  const _KasDexLaunchRequest({
    required this.name,
    required this.ticker,
    required this.supply,
    required this.seedToken,
    required this.seedKasSompi,
    required this.lockDays,
  });

  final String name;
  final String ticker;
  final BigInt supply;
  final BigInt seedToken;
  final BigInt seedKasSompi;
  final int lockDays;
}

class _KasDexLaunchDialog extends StatefulWidget {
  const _KasDexLaunchDialog();

  @override
  State<_KasDexLaunchDialog> createState() => _KasDexLaunchDialogState();
}

class _KasDexLaunchDialogState extends State<_KasDexLaunchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tickerController = TextEditingController();
  final _supplyController = TextEditingController();
  final _seedTokenController = TextEditingController();
  final _seedKasController = TextEditingController();
  final _lockDaysController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _tickerController.dispose();
    _supplyController.dispose();
    _seedTokenController.dispose();
    _seedKasController.dispose();
    _lockDaysController.dispose();
    super.dispose();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label wajib diisi.' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final supply = BigInt.parse(_supplyController.text.trim());
    final seedToken = BigInt.parse(_seedTokenController.text.trim());
    final seedKasSompi = parseKasAmount(_seedKasController.text);
    final lockDays = int.parse(_lockDaysController.text.trim());
    if (seedToken > supply) {
      _formKey.currentState!.validate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seed token tidak boleh melebihi supply.'),
        ),
      );
      return;
    }
    if (seedKasSompi == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah seed KAS tidak valid.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _KasDexLaunchRequest(
        name: _nameController.text.trim(),
        ticker: _tickerController.text.trim().toUpperCase(),
        supply: supply,
        seedToken: seedToken,
        seedKasSompi: seedKasSompi,
        lockDays: lockDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Deploy token KasDex'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama token'),
              validator: (value) {
                final required = _required(value, 'Nama token');
                if (required != null) return required;
                if (value!.trim().length < 2 || value.trim().length > 32) {
                  return 'Gunakan 2–32 karakter.';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _tickerController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Ticker'),
              validator: (value) {
                final required = _required(value, 'Ticker');
                if (required != null) return required;
                if (!RegExp(r'^[A-Za-z0-9]{2,8}$').hasMatch(value!.trim())) {
                  return 'Gunakan 2–8 huruf atau angka.';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _supplyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Supply token'),
              validator: (value) {
                final required = _required(value, 'Supply');
                if (required != null) return required;
                final parsed = BigInt.tryParse(value!.trim());
                return parsed == null || parsed < BigInt.from(1000)
                    ? 'Supply minimum 1.000 token.'
                    : null;
              },
            ),
            TextFormField(
              controller: _seedTokenController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Token untuk seed pool',
              ),
              validator: (value) {
                final required = _required(value, 'Seed token');
                if (required != null) return required;
                final parsed = BigInt.tryParse(value!.trim());
                return parsed == null || parsed < BigInt.from(100)
                    ? 'Seed minimum 100 token.'
                    : null;
              },
            ),
            TextFormField(
              controller: _seedKasController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Seed KAS (1–3.000 KAS pilot cap)',
                suffixText: 'KAS',
              ),
              validator: (value) {
                final amount = parseKasAmount(value ?? '');
                return amount == null || amount < BigInt.from(100000000)
                    ? 'Seed minimum 1 KAS, hingga 8 desimal.'
                    : amount > BigInt.from(300000000000)
                    ? 'Seed melebihi cap pilot 3.000 KAS.'
                    : null;
              },
            ),
            TextFormField(
              controller: _lockDaysController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Lock likuiditas (7–365 hari)',
              ),
              validator: (value) {
                final days = int.tryParse(value ?? '');
                return days == null || days < 7 || days > 365
                    ? 'Pilih 7 hingga 365 hari.'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Lanjutkan')),
    ],
  );
}

class KronMarketScreen extends StatefulWidget {
  const KronMarketScreen({
    required this.session,
    required this.onTradeSubmitted,
    super.key,
  });

  final KaspaWalletSession session;
  final Future<void> Function() onTradeSubmitted;

  @override
  State<KronMarketScreen> createState() => _KronMarketScreenState();
}

class _KronMarketScreenState extends State<KronMarketScreen> {
  final KronDiscoveryRepository _repository = KronDiscoveryRepository();
  final KasDexL1Repository _kasDexRepository = KasDexL1Repository();
  List<KronMarketListing> _markets = const [];
  List<KasDexL1Pool> _kasDexPools = const [];
  Map<String, KronVerifiedToken> _verifiedTokens = const {};
  Map<String, dynamic>? _kasDexHealth;
  bool _loading = true;
  bool _kasDexLoading = true;
  String? _error;
  String? _kasDexError;
  String? _kasDexHealthError;
  String _filter = 'semua';
  String _marketSource = 'KRON';

  @override
  void initState() {
    super.initState();
    _loadMarkets();
    _kasDexHealthTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshKasDexHealth(),
    );
  }

  Timer? _kasDexHealthTimer;

  @override
  void dispose() {
    _kasDexHealthTimer?.cancel();
    _repository.close();
    _kasDexRepository.close();
    super.dispose();
  }

  Future<void> _loadMarkets() async {
    setState(() {
      _loading = true;
      _kasDexLoading = true;
      _error = null;
      _kasDexError = null;
      _kasDexHealthError = null;
    });
    await Future.wait([_loadKronMarkets(), _loadKasDexMarkets()]);
  }

  Future<void> _loadKronMarkets() async {
    try {
      final results = await Future.wait([
        _repository.fetchMarkets(KronMarketKind.curve),
        _repository.fetchMarkets(KronMarketKind.pool),
        _repository.fetchVerifiedTokens(),
      ]);
      if (!mounted) return;
      final markets = [
        ...(results[0] as List<KronMarketListing>),
        ...(results[1] as List<KronMarketListing>),
      ];
      setState(() {
        _markets = markets;
        _verifiedTokens = {
          for (final token in results[2] as List<KronVerifiedToken>)
            token.covenantId.toLowerCase(): token,
        };
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Market KRON gagal dimuat: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadKasDexMarkets() async {
    try {
      final results = await Future.wait([
        _kasDexRepository.fetchHealth(),
        _kasDexRepository.fetchPools(),
      ]);
      if (!mounted) return;
      setState(() {
        _kasDexHealth = results[0] as Map<String, dynamic>;
        _kasDexPools = results[1] as List<KasDexL1Pool>;
        _kasDexLoading = false;
        _kasDexHealthError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _kasDexError = 'Market KasDex gagal dimuat: $error';
          _kasDexLoading = false;
        });
      }
    }
  }

  Future<void> _refreshKasDexHealth() async {
    try {
      final health = await _kasDexRepository.fetchHealth();
      if (!mounted) return;
      setState(() {
        _kasDexHealth = health;
        _kasDexHealthError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _kasDexHealth = null;
        _kasDexHealthError = '$error';
      });
    }
  }

  List<KronMarketListing> get _visibleMarkets => _markets
      .where(
        (market) => switch (_filter) {
          'pool' => market.graduated,
          'curve' => !market.graduated,
          _ => true,
        },
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final markets = _visibleMarkets;
    final kasDexHealthy =
        _kasDexHealth?['network'] == 'mainnet' &&
        _kasDexHealth?['pilot'] == true &&
        _kasDexHealth?['status'] == 'ok' &&
        _kasDexHealth?['node_connected'] == true &&
        _kasDexHealth?['contract_version'] == 5;
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        title: const Text('Market'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang market',
            onPressed: _loading ? null : _loadMarkets,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: _loadMarkets,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
          children: [
            const _SectionHeading(
              title: 'Market',
              subtitle: 'KRON dan KasDex L1 · harga dalam KAS',
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'KRON', label: Text('KRON')),
                ButtonSegment(value: 'KasDex', label: Text('KasDex L1')),
              ],
              selected: {_marketSource},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _marketSource = selection.first),
            ),
            const SizedBox(height: 12),
            if (_marketSource == 'KRON') ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'semua', label: Text('Semua')),
                  ButtonSegment(value: 'curve', label: Text('Kurva')),
                  ButtonSegment(value: 'pool', label: Text('Pool')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                _KronError(message: _error!, onRetry: _loadMarkets)
              else if (_loading && _markets.isEmpty)
                const _LoadingMessage(label: 'Memuat data market KRON…')
              else if (markets.isEmpty)
                const _EmptyMessage(message: 'Data market KRON tidak tersedia.')
              else
                for (final market in markets)
                  _KronMarketRow(
                    market: market,
                    verifiedToken:
                        _verifiedTokens[market.covenantId.toLowerCase()],
                    onTap: () => _showMarket(context, market),
                  ),
            ] else ...[
              if (_kasDexError != null)
                _KronError(message: _kasDexError!, onRetry: _loadMarkets)
              else if (_kasDexLoading && _kasDexPools.isEmpty)
                const _LoadingMessage(label: 'Memuat pool KasDex L1…')
              else ...[
                if (!kasDexHealthy)
                  Card(
                    color: const Color(0xFFFFF4DD),
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_rounded, color: _red),
                      title: const Text('KasDex L1 tidak siap untuk trading'),
                      subtitle: Text(
                        'Status: ${_kasDexHealthError ?? _kasDexHealth?['status'] ?? 'tidak diketahui'} · '
                        'node_connected: '
                        '${_kasDexHealth?['node_connected'] ?? 'tidak diketahui'}. '
                        'Tombol trading tetap dikunci sampai layanan pulih.',
                      ),
                      trailing: IconButton(
                        tooltip: 'Periksa kembali KasDex',
                        onPressed: _loadKasDexMarkets,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                  ),
                if (_kasDexPools.isEmpty)
                  const _EmptyMessage(message: 'Pool KasDex tidak tersedia.')
                else
                  for (final pool in _kasDexPools)
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _mint,
                          foregroundColor: _greenDark,
                          child: const Icon(Icons.token_rounded),
                        ),
                        title: Text('${pool.name} (${pool.ticker})'),
                        subtitle: Text(
                          '${formatKasAmount(pool.reserveKasSompi)} KAS · '
                          '${pool.reserveToken} token · '
                          '${pool.synced ? 'tersinkron' : 'belum sinkron'}'
                          '${pool.retired ? ' · retired' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showKasDexMarket(context, pool),
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showKasDexMarket(
    BuildContext context,
    KasDexL1Pool pool,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _KasDexMarketDetails(
        pool: pool,
        session: widget.session,
        onTradeSubmitted: widget.onTradeSubmitted,
        isServiceHealthy:
            _kasDexHealth?['network'] == 'mainnet' &&
            _kasDexHealth?['pilot'] == true &&
            _kasDexHealth?['status'] == 'ok' &&
            _kasDexHealth?['node_connected'] == true &&
            _kasDexHealth?['contract_version'] == 5,
      ),
    );
  }

  Future<void> _showMarket(
    BuildContext context,
    KronMarketListing market,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _KronMarketDetails(
        market: market,
        verifiedToken: _verifiedTokens[market.covenantId.toLowerCase()],
        session: widget.session,
        onTradeSubmitted: widget.onTradeSubmitted,
      ),
    );
  }
}

class _KasDexMarketDetails extends StatefulWidget {
  const _KasDexMarketDetails({
    required this.pool,
    required this.session,
    required this.onTradeSubmitted,
    required this.isServiceHealthy,
  });

  final KasDexL1Pool pool;
  final KaspaWalletSession session;
  final Future<void> Function() onTradeSubmitted;
  final bool isServiceHealthy;

  @override
  State<_KasDexMarketDetails> createState() => _KasDexMarketDetailsState();
}

class _KasDexMarketDetailsState extends State<_KasDexMarketDetails> {
  final KasDexL1Repository _repository = KasDexL1Repository();
  bool _busy = false;

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _trade({required bool buy}) async {
    if (_busy || !widget.isServiceHealthy || !widget.pool.synced) return;
    final amountText = await showDialog<String>(
      context: context,
      builder: (context) =>
          _KasDexTradeAmountDialog(ticker: widget.pool.ticker, buy: buy),
    );
    if (amountText == null || !mounted) return;
    final direction = buy ? 'kasForTok' : 'tokForKas';
    final amountIn = buy
        ? parseKasAmount(amountText)
        : BigInt.tryParse(amountText.trim());
    if (amountIn == null || amountIn <= BigInt.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            buy
                ? 'Masukkan jumlah KAS yang valid.'
                : 'Jumlah token harus bilangan bulat positif.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final quote = await _repository.quoteSwap(
        session: widget.session,
        pool: widget.pool,
        direction: direction,
        amountIn: amountIn,
      );
      if (!mounted) return;
      final spendText = buy
          ? '${formatKasAmount(quote.amountIn)} KAS'
          : '${quote.amountIn} ${widget.pool.ticker}';
      final receiveText = buy
          ? '${quote.amountOut} ${widget.pool.ticker}'
          : '${formatKasAmount(quote.amountOut)} KAS';
      final minimumText = buy
          ? '${quote.minimumAmountOut} ${widget.pool.ticker}'
          : '${formatKasAmount(quote.minimumAmountOut)} KAS';
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Konfirmasi ${buy ? 'beli' : 'jual'} KasDex'),
          content: Text(
            '${widget.pool.name} (${widget.pool.ticker})\n'
            'Anda kirim: $spendText\n'
            'Perkiraan diterima: $receiveText\n'
            'Minimum diterima (slippage 1%): $minimumText\n\n'
            'Transaksi akan ditandatangani wallet lokal dan dikirim melalui '
            'KasDex L1.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Konfirmasi & kirim'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final txid = await _repository.swap(
        session: widget.session,
        pool: widget.pool,
        direction: direction,
        amountIn: amountIn,
        reviewedQuote: quote,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Swap KasDex dikirim: ${_shortTransactionId(txid)}'),
          duration: const Duration(seconds: 8),
        ),
      );
      await widget.onTradeSubmitted();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Swap KasDex gagal: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.pool.name} (${widget.pool.ticker})',
            style: const TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pool KasDex L1 · ${widget.pool.synced ? 'tersinkron' : 'belum sinkron'}'
            '${widget.pool.retired ? ' · retired' : ''}',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 12),
          Text('Cadangan ${formatKasAmount(widget.pool.reserveKasSompi)} KAS'),
          Text('Cadangan ${widget.pool.reserveToken} ${widget.pool.ticker}'),
          const SizedBox(height: 16),
          if (!widget.isServiceHealthy ||
              !widget.pool.synced ||
              widget.pool.retired)
            const Text(
              'KasDex belum siap atau pool tidak aktif. Swap dikunci sampai '
              'node dan pool kembali sehat.',
              style: TextStyle(color: _red),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _trade(buy: true),
                    icon: const Icon(Icons.south_west_rounded),
                    label: const Text('Beli'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _trade(buy: false),
                    icon: const Icon(Icons.north_east_rounded),
                    label: const Text('Jual'),
                  ),
                ),
              ],
            ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          Text(
            'KasDex pilot mainnet. K-force mengunci swap saat health check '
            'gagal; node wallet tetap memakai endpoint yang dikonfigurasi.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _muted),
          ),
        ],
      ),
    ),
  );
}

class _KasDexTradeAmountDialog extends StatefulWidget {
  const _KasDexTradeAmountDialog({required this.ticker, required this.buy});

  final String ticker;
  final bool buy;

  @override
  State<_KasDexTradeAmountDialog> createState() =>
      _KasDexTradeAmountDialogState();
}

class _KasDexTradeAmountDialogState extends State<_KasDexTradeAmountDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final tokenAmount = BigInt.tryParse(value);
    final valid = widget.buy
        ? parseKasAmount(value) != null
        : tokenAmount != null && tokenAmount > BigInt.zero;
    if (!valid) {
      setState(
        () => _error = widget.buy
            ? 'Masukkan KAS valid hingga 8 desimal.'
            : 'Masukkan jumlah token bulat yang valid.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.buy ? 'Beli' : 'Jual'} ${widget.ticker}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: widget.buy
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.buy ? 'Jumlah KAS' : 'Jumlah token',
        suffixText: widget.buy ? 'KAS' : widget.ticker,
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Lihat quote')),
    ],
  );
}

class _KronMarketDetails extends StatefulWidget {
  const _KronMarketDetails({
    required this.market,
    required this.verifiedToken,
    required this.session,
    required this.onTradeSubmitted,
  });

  final KronMarketListing market;
  final KronVerifiedToken? verifiedToken;
  final KaspaWalletSession session;
  final Future<void> Function() onTradeSubmitted;

  @override
  State<_KronMarketDetails> createState() => _KronMarketDetailsState();
}

class _KronMarketDetailsState extends State<_KronMarketDetails> {
  final KronDiscoveryRepository _repository = KronDiscoveryRepository();
  KronMarketListing? _token;
  List<KronOhlc> _candles = const [];
  List<KronTrade> _trades = const [];
  final Map<String, String> _errors = {};
  final Set<String> _loading = {'token', 'chart', 'trades'};
  final KronNativeTradeService _tradeService = KronNativeTradeService();
  bool _tradeBusy = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _tradeService.close();
    _repository.close();
    super.dispose();
  }

  Future<void> _trade({required bool buy}) async {
    if (_tradeBusy) return;
    final market = _token ?? widget.market;
    final action = buy ? 'Beli' : 'Jual';
    final enteredAmount = await showDialog<String>(
      context: context,
      builder: (context) => _KronTradeAmountDialog(
        action: action,
        ticker: market.ticker,
        decimals: market.decimals,
        buy: buy,
      ),
    );
    if (enteredAmount == null || !mounted) return;
    final amount = buy
        ? parseKasAmount(enteredAmount)
        : parseKronTokenAmount(enteredAmount, market.decimals);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            buy
                ? 'Masukkan jumlah KAS valid hingga 8 desimal.'
                : 'Masukkan jumlah ${market.ticker} valid '
                      'hingga ${market.decimals} desimal.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _tradeBusy = true;
      _errors.remove('trade');
    });
    try {
      final built = await _tradeService.buildTrade(
        session: widget.session,
        market: market,
        buy: buy,
        amount: amount,
      );
      final quote = built.quote.toJson();
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _KronTradeConfirmation(quote: quote, decimals: market.decimals),
      );
      if (approved != true || !mounted) return;
      final txid = await widget.session.signAndSubmitKronPskt(
        txJsonString: built.txJsonString,
        signInputs: built.signInputs,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transaksi KRON dikirim: ${_shortTransactionId(txid)}'),
        ),
      );
      await widget.onTradeSubmitted();
    } catch (error) {
      if (mounted) {
        setState(() => _errors['trade'] = '$error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Transaksi KRON gagal: $error')));
      }
    } finally {
      if (mounted) setState(() => _tradeBusy = false);
    }
  }

  Future<void> _loadDetails() async {
    await Future.wait([_loadToken(), _loadCandles(), _loadTrades()]);
  }

  Future<void> _loadToken() async {
    try {
      final token = await _repository.fetchToken(widget.market.ticker);
      if (mounted) setState(() => _token = token);
    } catch (error) {
      if (mounted) setState(() => _errors['token'] = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading.remove('token'));
      }
    }
  }

  Future<void> _loadCandles() async {
    try {
      final candles = await _repository.fetchOhlc(widget.market.ticker);
      if (mounted) setState(() => _candles = candles);
    } catch (error) {
      if (mounted) setState(() => _errors['chart'] = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading.remove('chart'));
      }
    }
  }

  Future<void> _loadTrades() async {
    try {
      final trades = await _repository.fetchTrades(widget.market.ticker);
      if (mounted) setState(() => _trades = trades);
    } catch (error) {
      if (mounted) setState(() => _errors['trades'] = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading.remove('trades'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final market = _token ?? widget.market;
    final chartData = _candles
        .skip(_candles.length > 48 ? _candles.length - 48 : 0)
        .map((candle) => candle.close)
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 18),
            Text(
              widget.verifiedToken?.name ?? market.name,
              style: const TextStyle(
                color: _ink,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  market.ticker,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 9),
                _MarketStatus(
                  graduated: market.graduated,
                  dormant: market.dormant,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MarketMetric(
              label: 'Harga',
              value: _formatKas(market.priceKas, unit: 'KAS'),
            ),
            _MarketMetric(
              label: 'Perubahan 24 jam',
              value: _formatPercent(market.change24hPercent),
            ),
            _MarketMetric(
              label: 'Volume 24 jam',
              value: _formatKas(market.volume24hKas, unit: 'KAS'),
            ),
            _MarketMetric(
              label: 'TVL',
              value: _formatKas(market.totalValueLockedKas, unit: 'KAS'),
            ),
            _MarketMetric(
              label: 'Holder',
              value: market.holderCount.toString(),
            ),
            _MarketMetric(
              label: 'Supply tercetak',
              value: _tokenAmount(market.minted, market.decimals),
              showDivider: false,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _tradeBusy ? null : () => _trade(buy: true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Beli'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _tradeBusy ? null : () => _trade(buy: false),
                    icon: const Icon(Icons.remove_rounded),
                    label: const Text('Jual'),
                  ),
                ),
              ],
            ),
            if (_tradeBusy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 5),
              const Text(
                'Membangun transaksi dari state on-chain terbaru…',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
            if (_errors.containsKey('trade')) ...[
              const SizedBox(height: 8),
              _InlineDataError(message: _errors['trade']!),
            ],
            const SizedBox(height: 18),
            const Text(
              'Grafik 1 jam',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            if (_loading.contains('chart'))
              const _LoadingMessage(label: 'Mengambil candle KRON…')
            else if (_errors.containsKey('chart'))
              _InlineDataError(message: _errors['chart']!)
            else if (_candles.isEmpty)
              const _EmptyMessage(message: 'Tidak ada candle untuk token ini.')
            else
              SizedBox(
                height: 90,
                child: CustomPaint(
                  painter: _SparklinePainter(chartData),
                  size: Size.infinite,
                ),
              ),
            const SizedBox(height: 18),
            const Text(
              'Transaksi terbaru',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            if (_loading.contains('trades'))
              const _LoadingMessage(label: 'Mengambil transaksi KRON…')
            else if (_errors.containsKey('trades'))
              _InlineDataError(message: _errors['trades']!)
            else if (_trades.isEmpty)
              const _EmptyMessage(
                message: 'Tidak ada transaksi untuk token ini.',
              )
            else
              for (final trade in _trades) _TradeRow(trade: trade),
            if (_errors.containsKey('token')) ...[
              const SizedBox(height: 12),
              _InlineDataError(message: _errors['token']!),
            ],
          ],
        ),
      ),
    );
  }
}

class _KronMarketRow extends StatelessWidget {
  const _KronMarketRow({
    required this.market,
    required this.verifiedToken,
    required this.onTap,
  });

  final KronMarketListing market;
  final KronVerifiedToken? verifiedToken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              market.ticker.characters.first.toUpperCase(),
              style: const TextStyle(
                color: _greenDark,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        verifiedToken?.name ?? market.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    _MarketStatus(
                      graduated: market.graduated,
                      dormant: market.dormant,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${market.ticker} · ${_formatKas(market.priceKas, unit: 'KAS')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  '24 jam ${_formatKas(market.volume24hKas, unit: 'KAS')}'
                  ' · ${market.holderCount} holder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ],
      ),
    ),
  );
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance});

  final KronTokenBalance balance;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            balance.ticker.characters.first.toUpperCase(),
            style: const TextStyle(
              color: _greenDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            balance.ticker,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          _tokenAmount(balance.balance, balance.decimals),
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _MarketStatus extends StatelessWidget {
  const _MarketStatus({required this.graduated, required this.dormant});

  final bool graduated;
  final bool dormant;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: graduated || dormant ? const Color(0xFFEAEFEB) : _mint,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      graduated
          ? 'Pool'
          : dormant
          ? 'Dormant'
          : 'Kurva',
      style: TextStyle(
        color: graduated || dormant ? _muted : _greenDark,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final KronTrade trade;

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.side.toLowerCase() == 'buy';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      trade.timestampSeconds * 1000,
    ).toLocal();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Icon(
            isBuy ? Icons.north_east_rounded : Icons.south_east_rounded,
            color: isBuy ? _green : _red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trade.side.toUpperCase()} · ${trade.kind}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _shortDateTime(timestamp),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            _formatKas(trade.volumeKas, unit: 'KAS'),
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketMetric extends StatelessWidget {
  const _MarketMetric({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: BoxDecoration(
      border: showDivider
          ? const Border(bottom: BorderSide(color: _line))
          : null,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
    ],
  );
}

class _KronError extends StatelessWidget {
  const _KronError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECE9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: _red, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _red, fontSize: 12, height: 1.4),
          ),
        ),
        IconButton(
          tooltip: 'Coba lagi',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, color: _red),
        ),
      ],
    ),
  );
}

class _InlineDataError extends StatelessWidget {
  const _InlineDataError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(message, style: const TextStyle(color: _red, fontSize: 12)),
  );
}

class _LoadingMessage extends StatelessWidget {
  const _LoadingMessage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _green),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    ),
  );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, fontSize: 13),
      ),
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 4,
    decoration: BoxDecoration(
      color: _line,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    final minimum = values.reduce((left, right) => left < right ? left : right);
    final maximum = values.reduce((left, right) => left > right ? left : right);
    final range = maximum - minimum;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = range == 0
          ? size.height / 2
          : size.height - (values[index] - minimum) / range * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _green
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

bool _sameAddresses(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _tokenAmount(BigInt raw, int decimals) {
  if (decimals == 0) return raw.toString();
  final scale = BigInt.from(10).pow(decimals);
  final whole = raw ~/ scale;
  final fraction = (raw % scale).toString().padLeft(decimals, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
}

String _formatKas(double? amount, {required String unit}) {
  if (amount == null) return 'Tidak tersedia';
  final decimals = amount.abs() >= 1000
      ? 2
      : amount.abs() >= 1
      ? 4
      : 8;
  final formatted = amount
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  return '$formatted $unit';
}

class _KronTradeAmountDialog extends StatefulWidget {
  const _KronTradeAmountDialog({
    required this.action,
    required this.ticker,
    required this.decimals,
    required this.buy,
  });

  final String action;
  final String ticker;
  final int decimals;
  final bool buy;

  @override
  State<_KronTradeAmountDialog> createState() => _KronTradeAmountDialogState();
}

class _KronTradeAmountDialogState extends State<_KronTradeAmountDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.action} ${widget.ticker}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autocorrect: false,
      decoration: InputDecoration(
        labelText: widget.buy ? 'Jumlah KAS' : 'Jumlah ${widget.ticker}',
        suffixText: widget.buy ? 'KAS' : widget.ticker,
        helperText:
            'Maksimum ${widget.buy ? 8 : widget.decimals} angka desimal',
      ),
      onSubmitted: (_) => Navigator.pop(context, _controller.text),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

class _KronTradeConfirmation extends StatelessWidget {
  const _KronTradeConfirmation({required this.quote, required this.decimals});

  final Map<String, dynamic> quote;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final operation = quote['operation'] == 'buy' ? 'Beli' : 'Jual';
    final inputAmount = BigInt.parse(quote['inputAmount'] as String);
    final outputAmount = BigInt.parse(quote['outputAmount'] as String);
    final protocolFee = BigInt.parse(quote['quoteFee'] as String);
    final networkFee = BigInt.parse(quote['networkFee'] as String);
    final inputUnit = quote['inputUnit'] as String;
    final outputUnit = quote['outputUnit'] as String;
    final inputFormatted = inputUnit == 'KAS'
        ? '${formatKasAmount(inputAmount)} KAS'
        : '${_tokenAmount(inputAmount, decimals)} $inputUnit';
    final outputFormatted = outputUnit == 'KAS'
        ? '${formatKasAmount(outputAmount)} KAS'
        : '${_tokenAmount(outputAmount, decimals)} $outputUnit';
    final feeFormatted = '${formatKasAmount(protocolFee)} KAS';
    final networkFeeFormatted = '${formatKasAmount(networkFee)} KAS';
    final totalKas = inputUnit == 'KAS' ? inputAmount + networkFee : null;

    return AlertDialog(
      title: Text('Konfirmasi $operation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${quote['tokenName']} (${quote['ticker']})'),
            const SizedBox(height: 12),
            _confirmationRow('Market', quote['market'].toString()),
            _confirmationRow('Anda ${operation.toLowerCase()}', inputFormatted),
            _confirmationRow('Perkiraan diterima', outputFormatted),
            if (protocolFee > BigInt.zero)
              _confirmationRow('Biaya protokol / DEX', feeFormatted),
            _confirmationRow('Biaya jaringan', networkFeeFormatted),
            if (totalKas != null)
              _confirmationRow(
                'Total maksimum KAS',
                '${formatKasAmount(totalKas)} KAS',
              ),
            const SizedBox(height: 12),
            const Text(
              'State covenant dan UTXO diambil langsung sebelum PSKT dibuat. '
              'Tinjau jumlah dan biaya ini; signature baru dibuat setelah '
              'Anda menyetujui transaksi.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Konfirmasi & kirim'),
        ),
      ],
    );
  }

  Widget _confirmationRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

String _shortTransactionId(String transactionId) => transactionId.length <= 16
    ? transactionId
    : '${transactionId.substring(0, 8)}…${transactionId.substring(transactionId.length - 8)}';

String _formatPercent(double? change) => change == null
    ? 'Tidak tersedia'
    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';

String _shortDateTime(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
