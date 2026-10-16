import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:k_force/k_force.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;
import 'package:qr_flutter/qr_flutter.dart';

import 'src/amount_format.dart';
import 'src/kron_tabs.dart';

const _ink = Color(0xFF1B1E3B);
const _green = Color(0xFF5156D8);
const _greenDark = Color(0xFF373BA8);
const _mint = Color(0xFFE9EAFF);
const _paper = Color(0xFFF7F7FC);
const _line = Color(0xFFE1E2EF);
const _muted = Color(0xFF6E7088);
const _amber = Color(0xFFE9AE44);
const _red = Color(0xFFB64236);

class KForceApp extends StatefulWidget {
  const KForceApp({super.key});

  @override
  State<KForceApp> createState() => _KForceAppState();
}

enum _AppScreen { starting, welcome, recovery, confirmRecovery, import, wallet }

class _KForceAppState extends State<KForceApp> {
  final KaspaWalletCore _core = KaspaWalletCore(
    profile: KaspaNetworkProfile.mainnet,
  );
  _AppScreen _screen = _AppScreen.starting;
  KaspaWalletSession? _session;
  KaspaWalletSnapshot? _snapshot;
  List<kaspa.ApiTransaction> _transactions = const [];
  String? _pendingPhrase;
  List<int> _challengeIndexes = const [];
  String? _error;
  bool _busy = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      if (await _core.hasWallet) {
        await _enterWallet();
      } else if (mounted) {
        setState(() {
          _screen = _AppScreen.welcome;
          _busy = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _screen = _AppScreen.welcome;
        _busy = false;
        _error = 'Penyimpanan aman tidak dapat dibuka: $error';
      });
    }
  }

  void _beginCreate() {
    final phrase = _core.generateRecoveryPhrase();
    final random = Random.secure();
    final indexes = <int>{};
    while (indexes.length < 2) {
      indexes.add(random.nextInt(phrase.split(' ').length));
    }
    setState(() {
      _pendingPhrase = phrase;
      _challengeIndexes = indexes.toList()..sort();
      _error = null;
      _screen = _AppScreen.recovery;
    });
  }

  Future<void> _confirmRecovery() async {
    final phrase = _pendingPhrase;
    if (phrase == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _core.importWallet(phrase);
      _pendingPhrase = null;
      await _enterWallet();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Dompet belum tersimpan: $error';
      });
    }
  }

  Future<void> _importRecovery(String phrase, String passphrase) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _core.importWallet(phrase, passphrase: passphrase);
      await _enterWallet();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Frasa pemulihan tidak dapat diimpor: $error';
      });
    }
  }

  Future<void> _enterWallet() async {
    final session = await _core.unlock();
    if (!mounted) {
      await session.close();
      return;
    }
    final previous = _session;
    setState(() {
      _session = session;
      _screen = _AppScreen.wallet;
      _busy = false;
      _error = null;
    });
    if (previous != null && !identical(previous, session)) {
      await previous.close();
    }
    await _refreshWallet();
  }

  Future<void> _refreshWallet() async {
    final session = _session;
    if (session == null || _refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final snapshot = await session.refresh();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      try {
        final transactions = await session.transactions();
        if (mounted) setState(() => _transactions = transactions);
      } catch (error) {
        if (mounted) {
          setState(() => _error = 'Riwayat belum dapat dimuat: $error');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Koneksi wallet gagal: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _showReceive() async {
    final session = _session;
    if (session == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _ReceiveSheet(session: session),
    );
  }

  void _cancelRecovery() {
    setState(() {
      _pendingPhrase = null;
      _challengeIndexes = const [];
      _error = null;
      _screen = _AppScreen.welcome;
    });
  }

  Future<void> _showSend() async {
    final session = _session;
    if (session == null) return;
    final transactionId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _SendSheet(
        profile: session.profile,
        onSend: (destination, amount) =>
            session.send(destination: destination, amountSompi: amount),
      ),
    );
    if (transactionId == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Transaksi dikirim: ${_shortId(transactionId)}')),
    );
    await _refreshWallet();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-force',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          brightness: Brightness.light,
          surface: _paper,
        ),
        scaffoldBackgroundColor: _paper,
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _greenDark,
            minimumSize: const Size(48, 52),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: _buildScreen(),
    );
  }

  Widget _buildScreen() => switch (_screen) {
    _AppScreen.starting => const _StartingScreen(),
    _AppScreen.welcome => KForceWelcomeScreen(
      error: _error,
      onCreate: _beginCreate,
      onImport: () => setState(() {
        _error = null;
        _screen = _AppScreen.import;
      }),
    ),
    _AppScreen.recovery => _RecoveryScreen(
      phrase: _pendingPhrase ?? '',
      onBack: _cancelRecovery,
      onContinue: () => setState(() => _screen = _AppScreen.confirmRecovery),
    ),
    _AppScreen.confirmRecovery => _ConfirmRecoveryScreen(
      phrase: _pendingPhrase ?? '',
      indexes: _challengeIndexes,
      busy: _busy,
      error: _error,
      onBack: () => setState(() => _screen = _AppScreen.recovery),
      onConfirm: _confirmRecovery,
    ),
    _AppScreen.import => _ImportScreen(
      busy: _busy,
      error: _error,
      onBack: () => setState(() {
        _error = null;
        _screen = _AppScreen.welcome;
      }),
      onImport: _importRecovery,
    ),
    _AppScreen.wallet => _buildWalletTabs(),
  };

  Widget _buildWalletTabs() => KForceTabShell(
    portfolioPage: KronPortfolioScreen(
      balanceSompi: _snapshot?.balanceSompi,
      addresses:
          _snapshot?.addresses.map((address) => address.value).toList() ??
          const [],
      onRefreshWallet: _refreshWallet,
    ),
    walletPage: _WalletScreen(
      snapshot: _snapshot,
      transactions: _transactions,
      error: _error,
      refreshing: _refreshing,
      onRefresh: _refreshWallet,
      onReceive: _showReceive,
      onSend: _showSend,
    ),
    launchpadPage: KronLaunchpadScreen(
      session: _session!,
      onTradeSubmitted: _refreshWallet,
    ),
    marketPage: KronMarketScreen(
      session: _session!,
      onTradeSubmitted: _refreshWallet,
    ),
  );
}

class _StartingScreen extends StatelessWidget {
  const _StartingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: _green)),
  );
}

class KForceWelcomeScreen extends StatelessWidget {
  const KForceWelcomeScreen({
    super.key,
    required this.error,
    required this.onCreate,
    required this.onImport,
  });

  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(),
                  const Spacer(),
                  const Text(
                    'Kaspa,\ndi tanganmu.',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 38,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dompet mandiri untuk menyimpan dan mengirim KAS. '
                    'Kunci pemulihan tetap berada di perangkatmu.',
                    style: TextStyle(color: _muted, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (error != null) ...[
                    _InlineError(message: error!),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Buat dompet baru'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Pulihkan dengan frasa'),
                    ),
                  ),
                  const Spacer(),
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 17, color: _green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tidak ada akun kustodian. Simpan frasa pemulihan secara offline.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 11),
      const Text(
        'K-force',
        style: TextStyle(
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen({
    required this.phrase,
    required this.onBack,
    required this.onContinue,
  });

  final String phrase;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final words = phrase.split(' ');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Cadangkan dompet'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  const Text(
                    'Frasa pemulihan',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tulis 24 kata ini sesuai urutan dan simpan secara offline. '
                    'Siapa pun yang memilikinya dapat mengambil KAS-mu.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: _muted),
                  ),
                  const SizedBox(height: 20),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: words.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.35,
                        ),
                    itemBuilder: (context, index) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _line),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                words[index],
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _WarningStrip(
                    icon: Icons.visibility_off_outlined,
                    text:
                        'Jangan bagikan, foto, atau masukkan frasa ini ke situs lain.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('Lanjutkan verifikasi'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRecoveryScreen extends StatefulWidget {
  const _ConfirmRecoveryScreen({
    required this.phrase,
    required this.indexes,
    required this.busy,
    required this.error,
    required this.onBack,
    required this.onConfirm,
  });

  final String phrase;
  final List<int> indexes;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmRecoveryScreen> createState() => _ConfirmRecoveryScreenState();
}

class _ConfirmRecoveryScreenState extends State<_ConfirmRecoveryScreen> {
  final _controllers = [TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _matches {
    final words = widget.phrase.split(' ');
    return List.generate(widget.indexes.length, (index) {
      return _controllers[index].text.trim().toLowerCase() ==
          words[widget.indexes[index]];
    }).every((value) => value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: widget.busy ? null : widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Verifikasi cadangan'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          children: [
            const Text(
              'Pastikan frasamu tersimpan',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Masukkan kata yang diminta. Seed baru akan disimpan di perangkat setelah verifikasi berhasil.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            for (var index = 0; index < widget.indexes.length; index++) ...[
              TextFormField(
                controller: _controllers[index],
                enabled: !widget.busy,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Kata ke-${widget.indexes[index] + 1}',
                  prefixIcon: const Icon(Icons.tag_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.error != null) _InlineError(message: widget.error!),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.busy || !_matches ? null : widget.onConfirm,
                child: widget.busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Konfirmasi dan buka wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportScreen extends StatefulWidget {
  const _ImportScreen({
    required this.busy,
    required this.error,
    required this.onBack,
    required this.onImport,
  });

  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final Future<void> Function(String phrase, String passphrase) onImport;

  @override
  State<_ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<_ImportScreen> {
  final _phraseController = TextEditingController();
  final _passphraseController = TextEditingController();
  bool _showPassphrase = false;

  @override
  void dispose() {
    _phraseController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await widget.onImport(_phraseController.text, _passphraseController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kembali',
          onPressed: widget.busy ? null : widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Pulihkan wallet'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
          children: [
            const Text(
              'Masukkan frasa pemulihan',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gunakan 12 atau 24 kata BIP39. Frasa diperiksa di perangkat dan tidak dikirim ke node.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phraseController,
              enabled: !widget.busy,
              minLines: 4,
              maxLines: 6,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'Frasa pemulihan',
                hintText: 'Ketik atau tempel kata-kata sesuai urutan',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphraseController,
              enabled: !widget.busy,
              obscureText: !_showPassphrase,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Passphrase BIP39 (opsional)',
                suffixIcon: IconButton(
                  tooltip: _showPassphrase ? 'Sembunyikan' : 'Tampilkan',
                  onPressed: () =>
                      setState(() => _showPassphrase = !_showPassphrase),
                  icon: Icon(
                    _showPassphrase ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.error != null) ...[
              _InlineError(message: widget.error!),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.busy || _phraseController.text.trim().isEmpty
                    ? null
                    : _submit,
                child: widget.busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Pulihkan dan buka wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletScreen extends StatelessWidget {
  const _WalletScreen({
    required this.snapshot,
    required this.transactions,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
    required this.onReceive,
    required this.onSend,
  });

  final KaspaWalletSnapshot? snapshot;
  final List<kaspa.ApiTransaction> transactions;
  final String? error;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onReceive;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final addresses =
        snapshot?.addresses.map((address) => address.value).toSet() ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const _BrandMark(),
        actions: [
          if (refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: _green),
              ),
            )
          else
            IconButton(
              tooltip: 'Perbarui saldo dan riwayat',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: _green,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            _NetworkLine(
              snapshot: snapshot,
              connecting: refreshing,
              failed: error?.startsWith('Koneksi wallet gagal:') == true,
            ),
            const SizedBox(height: 22),
            const Text(
              'Saldo Kaspa',
              style: TextStyle(
                color: _muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (snapshot == null && refreshing)
              const SizedBox(
                height: 54,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _green,
                    ),
                  ),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  snapshot == null
                      ? 'Belum tersedia'
                      : '${formatKasAmount(snapshot!.balanceSompi)} KAS',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 31,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (snapshot != null) ...[
              const SizedBox(height: 5),
              Text(
                '${snapshot!.spendableUtxoCount} UTXO siap digunakan',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: const Text('Kirim'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReceive,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    label: const Text('Terima'),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              _InlineError(message: error!, onRetry: onRefresh),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Aktivitas',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (snapshot != null)
                  Text(
                    snapshot!.connectedEndpoint,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (transactions.isEmpty && snapshot != null && error == null)
              const _EmptyHistory()
            else
              for (final transaction in transactions)
                _TransactionRow(
                  transaction: transaction,
                  walletAddresses: addresses,
                ),
            if (snapshot == null && error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: _green)),
              ),
            const SizedBox(height: 18),
            const _WarningStrip(
              icon: Icons.public_rounded,
              text:
                  'Node publik dapat melihat alamat yang diperiksa wallet ini.',
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkLine extends StatelessWidget {
  const _NetworkLine({
    required this.snapshot,
    required this.connecting,
    required this.failed,
  });

  final KaspaWalletSnapshot? snapshot;
  final bool connecting;
  final bool failed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: failed
              ? _red
              : snapshot?.serverInfo.isSynced == true
              ? _green
              : _amber,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        failed
            ? 'Koneksi Kaspa mainnet terputus'
            : snapshot?.serverInfo.isSynced == true
            ? 'Kaspa mainnet · tersinkronisasi'
            : connecting
            ? 'Menghubungkan ke Kaspa mainnet'
            : 'Kaspa mainnet belum tersinkronisasi',
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 26),
    decoration: const BoxDecoration(
      border: Border(
        bottom: BorderSide(color: _line),
        top: BorderSide(color: _line),
      ),
    ),
    child: const Column(
      children: [
        Icon(Icons.receipt_long_outlined, color: _muted, size: 25),
        SizedBox(height: 9),
        Text('Belum ada transaksi terindeks', style: TextStyle(color: _muted)),
      ],
    ),
  );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.walletAddresses,
  });

  final kaspa.ApiTransaction transaction;
  final Set<String> walletAddresses;

  @override
  Widget build(BuildContext context) {
    final hasOwnedInput = transaction.inputs.any(
      (input) => walletAddresses.contains(input.previousOutpointAddress),
    );
    final inputsResolved = transaction.inputs.every(
      (input) => input.previousOutpointAddress != null,
    );
    final ownedOutputs = transaction.outputs
        .where(
          (output) => walletAddresses.contains(output.scriptPublicKeyAddress),
        )
        .fold<BigInt>(
          BigInt.zero,
          (total, output) => total + BigInt.from(output.amount),
        );
    final ownedInputRows = transaction.inputs
        .where(
          (input) => walletAddresses.contains(input.previousOutpointAddress),
        )
        .toList(growable: false);
    final ownedInputsComplete = ownedInputRows.every(
      (input) => input.previousOutpointAmount != null,
    );
    final ownedInputs = ownedInputRows.fold<BigInt>(BigInt.zero, (
      total,
      input,
    ) {
      final amount = input.previousOutpointAmount;
      return amount == null ? total : total + BigInt.from(amount);
    });
    final isOutgoing = hasOwnedInput;
    final isIncoming =
        !hasOwnedInput && inputsResolved && ownedOutputs > BigInt.zero;
    final hasAmount = isOutgoing
        ? ownedInputRows.isNotEmpty && ownedInputsComplete
        : isIncoming && ownedOutputs > BigInt.zero;
    final amount = isOutgoing ? ownedInputs - ownedOutputs : ownedOutputs;
    final transactionType = isOutgoing
        ? 'Keluar'
        : isIncoming
        ? 'Masuk'
        : 'Transaksi';
    final date = transaction.blockTime > 0
        ? DateTime.fromMillisecondsSinceEpoch(transaction.blockTime).toLocal()
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOutgoing
                  ? const Color(0xFFFFECE9)
                  : isIncoming
                  ? _mint
                  : const Color(0xFFEAEFEB),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              isOutgoing
                  ? Icons.north_east_rounded
                  : isIncoming
                  ? Icons.south_west_rounded
                  : Icons.swap_horiz_rounded,
              color: isOutgoing
                  ? _red
                  : isIncoming
                  ? _green
                  : _muted,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transactionType,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date == null
                      ? (transaction.isAccepted
                            ? 'Diterima'
                            : 'Menunggu penerimaan')
                      : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${_shortId(transaction.transactionId)}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (hasAmount) ...[
            const SizedBox(width: 8),
            Text(
              '${isOutgoing ? '-' : '+'}${formatKasAmount(amount)}',
              style: TextStyle(
                color: isOutgoing ? _ink : _green,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.session});

  final KaspaWalletSession session;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  late final Future<String> _address = widget.session.receiveAddress();
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 20 + bottom),
        child: FutureBuilder<String>(
          future: _address,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _SheetError(
                title: 'Alamat belum dapat dibuat',
                message: '${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator(color: _green)),
              );
            }
            final address = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SheetHandle(),
                  const SizedBox(height: 18),
                  const Text(
                    'Terima KAS',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  QrImageView(
                    data: address,
                    size: 210,
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: _ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: address));
                        if (mounted) setState(() => _copied = true);
                      },
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                      ),
                      label: Text(_copied ? 'Alamat disalin' : 'Salin alamat'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Kirim hanya KAS melalui jaringan Kaspa mainnet ke alamat ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.profile, required this.onSend});

  final KaspaNetworkProfile profile;
  final Future<String> Function(String destination, BigInt amount) onSend;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final destination = _addressController.text.trim();
    final amount = parseKasAmount(_amountController.text)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi pengiriman'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatKasAmount(amount)} KAS',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 8),
            SelectableText(destination, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            const Text(
              'Biaya jaringan ditambahkan sesuai estimasi node. Transaksi yang disiarkan tidak dapat dibatalkan.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Periksa lagi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kirim KAS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final transactionId = await widget.onSend(destination, amount);
      if (mounted) Navigator.pop(context, transactionId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Transaksi gagal dikirim: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 20 + bottom),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              const Text(
                'Kirim KAS',
                style: TextStyle(
                  color: _ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _addressController,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: 'Alamat tujuan',
                  hintText: 'kaspa:…',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (value) {
                  final address = value?.trim() ?? '';
                  if (!kaspa.Address.isValid(
                    address,
                    kaspa.addressPrefixForNetwork(widget.profile.network),
                  )) {
                    return 'Alamat Kaspa mainnet tidak valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  suffixText: 'KAS',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  if (parseKasAmount(value ?? '') == null) {
                    return 'Masukkan jumlah lebih dari 0, maksimal 8 angka desimal';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                  label: Text(_busy ? 'Menyiarkan transaksi…' : 'Lanjutkan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 34,
      height: 4,
      decoration: BoxDecoration(
        color: _line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _SheetError extends StatelessWidget {
  const _SheetError({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: _red, size: 30),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WarningStrip extends StatelessWidget {
  const _WarningStrip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _mint,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _greenDark, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _greenDark,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFECE9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: _red, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _red, fontSize: 12, height: 1.4),
          ),
        ),
        if (onRetry != null)
          IconButton(
            tooltip: 'Coba lagi',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: _red),
          ),
      ],
    ),
  );
}

String _shortId(String value) => value.length <= 14
    ? value
    : '${value.substring(0, 8)}…${value.substring(value.length - 4)}';
