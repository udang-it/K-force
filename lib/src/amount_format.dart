BigInt? parseKasAmount(String value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,8}))?$').firstMatch(value.trim());
  if (match == null) return null;
  final whole = BigInt.tryParse(match.group(1)!);
  final fraction = BigInt.tryParse((match.group(2) ?? '').padRight(8, '0'));
  if (whole == null || fraction == null) return null;
  final amount = whole * BigInt.from(100000000) + fraction;
  return amount > BigInt.zero ? amount : null;
}

String formatKasAmount(BigInt amount) {
  final whole = amount ~/ BigInt.from(100000000);
  final fraction = (amount % BigInt.from(100000000)).toString().padLeft(8, '0');
  final trimmedFraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmedFraction.isEmpty ? '$whole' : '$whole.$trimmedFraction';
}
