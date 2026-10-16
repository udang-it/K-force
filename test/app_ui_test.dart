import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/app.dart';
import 'package:k_force/src/amount_format.dart';
import 'package:k_force/src/kron_tabs.dart';

void main() {
  test('jumlah KAS diparse tepat ke sompi', () {
    expect(parseKasAmount('1'), BigInt.from(100000000));
    expect(parseKasAmount('1.00000001'), BigInt.from(100000001));
    expect(parseKasAmount('0.00000001'), BigInt.one);
    expect(parseKasAmount('0'), isNull);
    expect(parseKasAmount('1.000000001'), isNull);
    expect(parseKasAmount('1e3'), isNull);
    expect(formatKasAmount(BigInt.from(100000001)), '1.00000001');
  });

  testWidgets('layar awal muat dan aksi pembuatan dompet dapat dipilih', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var createTapped = false;
    var importTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: KForceWelcomeScreen(
          error: null,
          onCreate: () => createTapped = true,
          onImport: () => importTapped = true,
        ),
      ),
    );

    expect(find.text('K-force'), findsOneWidget);
    expect(find.text('Buat dompet baru'), findsOneWidget);
    expect(find.text('Pulihkan dengan frasa'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        home: KForceWelcomeScreen(
          error: null,
          onCreate: () => createTapped = true,
          onImport: () => importTapped = true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Buat dompet baru'));
    expect(createTapped, isTrue);
    await tester.tap(find.text('Pulihkan dengan frasa'));
    expect(importTapped, isTrue);
  });

  testWidgets('bottom navigation berpindah ke halaman yang dipilih', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: KForceTabShell(
          portfolioPage: const _NavigationTestPage(label: 'Portofolio'),
          walletPage: const _NavigationTestPage(label: 'Wallet'),
          launchpadPage: const _NavigationTestPage(label: 'Launchpad'),
          marketPage: const _NavigationTestPage(label: 'Market'),
        ),
      ),
    );
    expect(find.text('Halaman Portofolio'), findsOneWidget);
    expect(
      tester
          .widgetList<NavigationDestination>(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byType(NavigationDestination),
            ),
          )
          .map((destination) => destination.label),
      ['Portofolio', 'Wallet', 'Launchpad', 'Market'],
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Halaman Wallet'), findsOneWidget);

    await tester.tap(find.text('Launchpad'));
    await tester.pumpAndSettle();
    expect(find.text('Halaman Launchpad'), findsOneWidget);

    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(find.text('Halaman Market'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _NavigationTestPage extends StatelessWidget {
  const _NavigationTestPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Halaman $label')));
}
