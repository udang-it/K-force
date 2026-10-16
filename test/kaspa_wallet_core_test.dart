import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/k_force.dart';
import 'package:kaspium_wallet/kaspa/kaspa.dart' as kaspa;

void main() {
  const recoveryPhrase =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  test('frasa baru berisi 24 kata valid sebelum seed disimpan', () {
    final core = KaspaWalletCore(profile: KaspaNetworkProfile.mainnet);
    final phrase = core.generateRecoveryPhrase();

    expect(phrase.split(' '), hasLength(24));
    expect(kaspa.isValidMnemonic(phrase), isTrue);
  });

  test('menurunkan alamat Schnorr mainnet dari frasa BIP39', () {
    final address = KaspaWalletCore.deriveAddressFromMnemonic(recoveryPhrase);

    expect(address.startsWith('kaspa:'), isTrue);
    expect(kaspa.Address.isValid(address, kaspa.AddressPrefix.kaspa), isTrue);
    expect(KaspaWalletCore.deriveAddressFromMnemonic(recoveryPhrase), address);
  });

  test('alamat receive, change, dan testnet mengikuti prefix jaringan', () {
    final receive = KaspaWalletCore.deriveAddressFromMnemonic(recoveryPhrase);
    final change = KaspaWalletCore.deriveAddressFromMnemonic(
      recoveryPhrase,
      typeIndex: 1,
    );
    final testnet = KaspaWalletCore.deriveAddressFromMnemonic(
      recoveryPhrase,
      network: kaspa.KaspaNetwork.testnet,
    );
    final secondReceive = KaspaWalletCore.deriveAddressFromMnemonic(
      recoveryPhrase,
      addressIndex: 1,
    );

    expect(receive, isNot(change));
    expect(receive, isNot(secondReceive));
    expect(testnet.startsWith('kaspatest:'), isTrue);
    expect(
      kaspa.Address.isValid(testnet, kaspa.AddressPrefix.kaspaTest),
      isTrue,
    );
  });

  test('menolak frasa pemulihan dengan checksum salah', () {
    expect(
      () => KaspaWalletCore.deriveAddressFromMnemonic(
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon',
      ),
      throwsFormatException,
    );
  });
}
