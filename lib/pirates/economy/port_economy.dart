import 'dart:math';

/// Deterministic quotes. Future bonuses enter as multipliers, never through CP.
abstract final class PortEconomy {
  static const cargoUnitValue = 2, repairPerHp = 1.0, recruitPerCrew = 1.0;
  static const serviceSeconds = 2.0, assistedServiceSeconds = 10.0;
  static int sale(int units, {double multiplier = 1}) =>
      (units * cargoUnitValue * multiplier).floor();
  static int repair(double missing, {double multiplier = 1}) =>
      (max(0, missing) * repairPerHp * multiplier).ceil();
  static int recruitment(int missing, {double multiplier = 1}) =>
      (max(0, missing) * recruitPerCrew * multiplier).ceil();
}

class PortReceipt {
  final String shipId, port;
  final int units, proceeds, repairQuote, crewQuote, repairPaid, crewPaid;
  const PortReceipt(
    this.shipId,
    this.port,
    this.units,
    this.proceeds,
    this.repairQuote,
    this.crewQuote,
    this.repairPaid,
    this.crewPaid,
  );
  int get net => proceeds - repairPaid - crewPaid;
  int get aid => repairQuote + crewQuote - repairPaid - crewPaid;
  Map<String, dynamic> toJson() => {
    'ship': shipId,
    'port': port,
    'units': units,
    'proceeds': proceeds,
    'repairQuote': repairQuote,
    'crewQuote': crewQuote,
    'repairPaid': repairPaid,
    'crewPaid': crewPaid,
  };
  factory PortReceipt.fromJson(Map<String, dynamic> j) {
    int amount(String key) {
      final v = j[key];
      if (v is! int || v < 0) {
        throw const FormatException('Invalid port ledger');
      }
      return v;
    }

    final r = PortReceipt(
      j['ship'],
      j['port'],
      amount('units'),
      amount('proceeds'),
      amount('repairQuote'),
      amount('crewQuote'),
      amount('repairPaid'),
      amount('crewPaid'),
    );
    if (r.repairPaid > r.repairQuote || r.crewPaid > r.crewQuote) {
      throw const FormatException('Invalid port costs');
    }
    return r;
  }
}
