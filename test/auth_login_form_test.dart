import 'dart:async';

import 'package:farmacia_prenotazioni/widgets/auth_login_form.dart';
import 'package:farmacia_prenotazioni/services/password_save.dart';
import 'package:farmacia_prenotazioni/widgets/staff_idle_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('form login: AutofillGroup, username/email, password, Invio invia', (tester) async {
    final email = TextEditingController();
    final password = TextEditingController();
    addTearDown(email.dispose);
    addTearDown(password.dispose);
    var submitted = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuthLoginForm(email: email, password: password, onSubmit: () => submitted++),
      ),
    ));

    expect(find.byType(AutofillGroup), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields, hasLength(2));
    expect(fields[0].keyboardType, TextInputType.emailAddress);
    expect(fields[0].autofillHints, containsAll([AutofillHints.username, AutofillHints.email]));
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].obscureText, isTrue);
    expect(fields[1].autofillHints, contains(AutofillHints.password));
    expect(fields[1].textInputAction, TextInputAction.done);

    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 1);
  });

  test('idle staff: avviso a 38 minuti, logout a 40, Resta connesso rinnova', () {
    final pending = <Duration, List<void Function()>>{};
    Timer schedule(Duration d, void Function() cb) {
      late Timer timer;
      void run() {
        if (!timer.isActive) return;
        timer.cancel();
        cb();
      }
      (pending[d] ??= []).add(run);
      timer = Timer(const Duration(days: 365), () {});
      // Avvolgiamo cancel per togliere il callback dalla coda.
      return _CancelHook(timer, () { pending[d]?.remove(run); });
    }

    void fire(Duration d) {
      final cbs = List<void Function()>.from(pending[d] ?? const []);
      pending[d]?.clear();
      for (final cb in cbs) {
        cb();
      }
    }

    var warns = 0;
    var logouts = 0;
    final c = StaffIdleController(
      onWarn: () => warns++,
      onLogout: () => logouts++,
      schedule: schedule,
    )..start();

    fire(const Duration(minutes: 37));
    expect(warns, 0);
    expect(logouts, 0);
    fire(const Duration(minutes: 38));
    expect(warns, 1);
    expect(logouts, 0);
    c.ping();
    fire(const Duration(minutes: 38));
    expect(warns, 2);
    expect(logouts, 0);
    fire(const Duration(minutes: 40));
    expect(logouts, 1);
    c.dispose();
  });

  test('storeBrowserPassword sul VM non fa nulla (solo web)', () async {
    expect(await storeBrowserPassword('a@b.it', 'x'), isFalse);
    expect(await getSavedBrowserPassword(), isNull);
  });
}


class _CancelHook implements Timer {
  _CancelHook(this._inner, this._onCancel);
  final Timer _inner;
  final void Function() _onCancel;
  @override
  void cancel() {
    if (!_inner.isActive) return;
    _inner.cancel();
    _onCancel();
  }
  @override
  bool get isActive => _inner.isActive;
  @override
  int get tick => _inner.tick;
}
