import 'dart:async';

import 'package:flutter/material.dart';

/// Timeout di inattività per staff/admin e preavviso (2 minuti prima).
const staffIdleTimeout = Duration(minutes: 40);
const staffIdleWarnBefore = Duration(minutes: 2);

final farmaciaNavigatorKey = GlobalKey<NavigatorState>();

/// Attiva il presidio di inattività solo mentre è aperta un'area staff/admin.
class StaffIdleWatch extends ChangeNotifier {
  StaffIdleWatch();
  static final instance = StaffIdleWatch();

  bool _active = false;
  bool get active => _active;

  void activate() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void deactivate() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// Logica pura (timer) per i test, senza Firebase.
class StaffIdleController {
  StaffIdleController({
    this.timeout = staffIdleTimeout,
    this.warnBefore = staffIdleWarnBefore,
    required this.onWarn,
    required this.onLogout,
    Timer Function(Duration duration, void Function() callback)? schedule,
  }) : schedule = schedule ?? Timer.new;

  final Duration timeout;
  final Duration warnBefore;
  final VoidCallback onWarn;
  final VoidCallback onLogout;
  final Timer Function(Duration duration, void Function() callback) schedule;

  Timer? _warn;
  Timer? _logout;
  bool warned = false;

  Duration get warnAfter {
    final d = timeout - warnBefore;
    return d.isNegative ? Duration.zero : d;
  }

  void start() {
    ping();
  }

  void ping() {
    warned = false;
    _warn?.cancel();
    _logout?.cancel();
    _warn = schedule(warnAfter, () {
      warned = true;
      onWarn();
    });
    _logout = schedule(timeout, onLogout);
  }

  void dispose() {
    _warn?.cancel();
    _logout?.cancel();
  }
}

