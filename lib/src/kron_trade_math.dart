const _scale = 1000000;
const _feeOutputMin = 20000000;

class KronCurveState {
  const KronCurveState({
    required this.realKas,
    required this.tokenReserve,
    required this.vKas,
    required this.graduationKas,
    required this.creatorFeeBps,
    required this.platformFeeBps,
    this.devFundBps,
  });

  final BigInt realKas;
  final BigInt tokenReserve;
  final BigInt vKas;
  final BigInt graduationKas;
  final BigInt creatorFeeBps;
  final BigInt platformFeeBps;
  final BigInt? devFundBps;
}

class KronCurveBuyQuote {
  const KronCurveBuyQuote({
    required this.kasIn,
    required this.tokenOut,
    required this.creatorFee,
    required this.platformFee,
    required this.devFundFee,
    required this.fee,
    required this.total,
    required this.newRealKas,
    required this.newTokenReserve,
  });

  final BigInt kasIn;
  final BigInt tokenOut;
  final BigInt creatorFee;
  final BigInt platformFee;
  final BigInt devFundFee;
  final BigInt fee;
  final BigInt total;
  final BigInt newRealKas;
  final BigInt newTokenReserve;
}

class KronCurveSellQuote {
  const KronCurveSellQuote({
    required this.tokenIn,
    required this.kasOut,
    required this.creatorFee,
    required this.platformFee,
    required this.devFundFee,
    required this.fee,
    required this.net,
    required this.newRealKas,
    required this.newTokenReserve,
  });

  final BigInt tokenIn;
  final BigInt kasOut;
  final BigInt creatorFee;
  final BigInt platformFee;
  final BigInt devFundFee;
  final BigInt fee;
  final BigInt net;
  final BigInt newRealKas;
  final BigInt newTokenReserve;

  BigInt get kasOutUnits => kasOut ~/ BigInt.from(_scale);
}

class KronPoolState {
  const KronPoolState({
    required this.kasReserve,
    required this.tokenReserve,
    required this.totalShares,
  });

  final BigInt kasReserve;
  final BigInt tokenReserve;
  final BigInt totalShares;
}

class KronPoolParams {
  const KronPoolParams({
    required this.creatorFeeBps,
    required this.platformFeeBps,
    required this.lpFeeBps,
    required this.lockedShares,
  });

  final BigInt creatorFeeBps;
  final BigInt platformFeeBps;
  final BigInt lpFeeBps;
  final BigInt lockedShares;
}

class KronPoolBuyQuote {
  const KronPoolBuyQuote({
    required this.kasIn,
    required this.tokenOut,
    required this.creatorFee,
    required this.platformFee,
    required this.creatorOut,
    required this.platformOut,
    required this.total,
    required this.newKas,
    required this.newToken,
  });

  final BigInt kasIn;
  final BigInt tokenOut;
  final BigInt creatorFee;
  final BigInt platformFee;
  final BigInt creatorOut;
  final BigInt platformOut;
  final BigInt total;
  final BigInt newKas;
  final BigInt newToken;
}

class KronPoolSellQuote {
  const KronPoolSellQuote({
    required this.tokenIn,
    required this.kasOut,
    required this.kasOutUnits,
    required this.creatorFee,
    required this.platformFee,
    required this.creatorOut,
    required this.platformOut,
    required this.net,
    required this.newKas,
    required this.newToken,
  });

  final BigInt tokenIn;
  final BigInt kasOut;
  final BigInt kasOutUnits;
  final BigInt creatorFee;
  final BigInt platformFee;
  final BigInt creatorOut;
  final BigInt platformOut;
  final BigInt net;
  final BigInt newKas;
  final BigInt newToken;
}

KronCurveBuyQuote? quoteKronCurveBuy(KronCurveState state, BigInt kasInSompi) {
  final kasIn = (kasInSompi ~/ BigInt.from(_scale)) * BigInt.from(_scale);
  if (kasIn <= BigInt.zero) return null;
  final newRealKas = state.realKas + kasIn;
  if (newRealKas > BigInt.from(900000000000000)) return null;
  final reserveUnits = state.realKas ~/ BigInt.from(_scale);
  final invariant = (state.vKas + reserveUnits) * state.tokenReserve;
  final newTokenReserve = _ceilDiv(
    invariant,
    state.vKas + reserveUnits + kasIn ~/ BigInt.from(_scale),
  );
  final tokenOut = state.tokenReserve - newTokenReserve;
  if (tokenOut <= BigInt.zero) return null;
  final creatorFee = _padFee(kasIn * state.creatorFeeBps ~/ BigInt.from(10000));
  final platformFee = _padFee(
    kasIn * state.platformFeeBps ~/ BigInt.from(10000),
  );
  final devFundFee = (state.devFundBps ?? BigInt.zero) > BigInt.zero
      ? _padFee(kasIn * state.devFundBps! ~/ BigInt.from(10000))
      : BigInt.zero;
  final fee = creatorFee + platformFee + devFundFee;
  return KronCurveBuyQuote(
    kasIn: kasIn,
    tokenOut: tokenOut,
    creatorFee: creatorFee,
    platformFee: platformFee,
    devFundFee: devFundFee,
    fee: fee,
    total: kasIn + fee,
    newRealKas: newRealKas,
    newTokenReserve: newTokenReserve,
  );
}

KronCurveSellQuote? quoteKronCurveSell(KronCurveState state, BigInt tokenIn) {
  if (tokenIn <= BigInt.zero) return null;
  final reserveUnits = state.realKas ~/ BigInt.from(_scale);
  final invariant = (state.vKas + reserveUnits) * state.tokenReserve;
  final newTokenReserve = state.tokenReserve + tokenIn;
  final minKasUnits = _ceilDiv(invariant, newTokenReserve) - state.vKas;
  final newKasUnits = minKasUnits < BigInt.zero ? BigInt.zero : minKasUnits;
  final kasOutUnits = reserveUnits - newKasUnits;
  if (kasOutUnits <= BigInt.zero) return null;
  final kasOut = kasOutUnits * BigInt.from(_scale);
  if (kasOut >= state.realKas) return null;
  final creatorFee = _padFee(
    kasOut * state.creatorFeeBps ~/ BigInt.from(10000),
  );
  final platformFee = _padFee(
    kasOut * state.platformFeeBps ~/ BigInt.from(10000),
  );
  final devFundFee = (state.devFundBps ?? BigInt.zero) > BigInt.zero
      ? _padFee(kasOut * state.devFundBps! ~/ BigInt.from(10000))
      : BigInt.zero;
  final fee = creatorFee + platformFee + devFundFee;
  final net = kasOut - fee;
  if (net <= BigInt.zero) return null;
  return KronCurveSellQuote(
    tokenIn: tokenIn,
    kasOut: kasOut,
    creatorFee: creatorFee,
    platformFee: platformFee,
    devFundFee: devFundFee,
    fee: fee,
    net: net,
    newRealKas: state.realKas - kasOut,
    newTokenReserve: newTokenReserve,
  );
}

KronPoolBuyQuote? quoteKronPoolBuy(
  KronPoolState state,
  KronPoolParams params,
  BigInt kasInSompi,
) {
  final scale = BigInt.from(_scale);
  if (state.totalShares <= BigInt.zero ||
      params.lockedShares < BigInt.zero ||
      params.lockedShares > state.totalShares) {
    return null;
  }
  final kasInUnits = kasInSompi ~/ scale;
  if (kasInUnits <= BigInt.zero) return null;
  final newKas = state.kasReserve + kasInUnits;
  final oldInvariant = state.kasReserve * state.tokenReserve;
  final retainWeight =
      params.lpFeeBps * (state.totalShares - params.lockedShares);
  final retainedKas = retainWeight <= BigInt.zero
      ? BigInt.zero
      : _ceilDiv(
          kasInUnits * retainWeight,
          BigInt.from(10000) * state.totalShares,
        );
  final effectiveKas = newKas - retainedKas;
  if (effectiveKas <= BigInt.zero) return null;
  final newToken = _ceilDiv(oldInvariant, effectiveKas);
  final tokenOut = state.tokenReserve - newToken;
  if (tokenOut <= BigInt.zero) return null;
  final kasIn = kasInUnits * scale;
  final lpFee = kasIn * params.lpFeeBps ~/ BigInt.from(10000);
  final creatorFee = kasIn * params.creatorFeeBps ~/ BigInt.from(10000);
  final creatorFloorRent = lpFee * params.lockedShares ~/ state.totalShares;
  final platformFee = kasIn * params.platformFeeBps ~/ BigInt.from(10000);
  final creatorOut = _padFee(creatorFee + creatorFloorRent);
  final platformOut = _padFee(platformFee);
  return KronPoolBuyQuote(
    kasIn: kasIn,
    tokenOut: tokenOut,
    creatorFee: creatorFee,
    platformFee: platformFee,
    creatorOut: creatorOut,
    platformOut: platformOut,
    total: kasIn + creatorOut + platformOut,
    newKas: newKas,
    newToken: newToken,
  );
}

KronPoolSellQuote? quoteKronPoolSell(
  KronPoolState state,
  KronPoolParams params,
  BigInt tokenIn,
) {
  if (tokenIn <= BigInt.zero ||
      state.totalShares <= BigInt.zero ||
      params.lockedShares < BigInt.zero ||
      params.lockedShares > state.totalShares) {
    return null;
  }
  final newToken = state.tokenReserve + tokenIn;
  final oldInvariant = state.kasReserve * state.tokenReserve;
  final effectiveMin = _ceilDiv(oldInvariant, newToken);
  final budget = state.kasReserve - effectiveMin;
  if (budget <= BigInt.zero) return null;
  final voluntaryShares = state.totalShares - params.lockedShares;
  final denominator =
      BigInt.from(10000) * state.totalShares +
      params.lpFeeBps * voluntaryShares;
  var kasOutUnits =
      budget * BigInt.from(10000) * state.totalShares ~/ denominator;
  BigInt retained(BigInt amount) {
    final weight = params.lpFeeBps * voluntaryShares;
    return weight <= BigInt.zero
        ? BigInt.zero
        : _ceilDiv(amount * weight, BigInt.from(10000) * state.totalShares);
  }

  BigInt charged(BigInt amount) => amount + retained(amount);
  while (kasOutUnits > BigInt.zero && charged(kasOutUnits) > budget) {
    kasOutUnits -= BigInt.one;
  }
  while (charged(kasOutUnits + BigInt.one) <= budget) {
    kasOutUnits += BigInt.one;
  }
  final newKas = state.kasReserve - kasOutUnits;
  if (kasOutUnits <= BigInt.zero || newKas < BigInt.one) return null;
  final kasOut = kasOutUnits * BigInt.from(_scale);
  final lpFee = kasOut * params.lpFeeBps ~/ BigInt.from(10000);
  final creatorFee = kasOut * params.creatorFeeBps ~/ BigInt.from(10000);
  final creatorFloorRent = lpFee * params.lockedShares ~/ state.totalShares;
  final platformFee = kasOut * params.platformFeeBps ~/ BigInt.from(10000);
  final creatorOut = _padFee(creatorFee + creatorFloorRent);
  final platformOut = _padFee(platformFee);
  final net = kasOut - creatorOut - platformOut;
  if (net <= BigInt.zero) return null;
  return KronPoolSellQuote(
    tokenIn: tokenIn,
    kasOut: kasOut,
    kasOutUnits: kasOutUnits,
    creatorFee: creatorFee,
    platformFee: platformFee,
    creatorOut: creatorOut,
    platformOut: platformOut,
    net: net,
    newKas: newKas,
    newToken: newToken,
  );
}

BigInt _ceilDiv(BigInt numerator, BigInt denominator) =>
    (numerator + denominator - BigInt.one) ~/ denominator;

BigInt _padFee(BigInt fee) {
  final minimum = BigInt.from(_feeOutputMin);
  return fee > minimum ? fee : minimum;
}
