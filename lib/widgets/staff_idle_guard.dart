import 'package:flutter/material.dart';
import '../screens/role_picker.dart';
import '../services/staff_auth.dart';
import 'staff_idle_controller.dart';
export 'staff_idle_controller.dart';

/// Intercetta pointer/scroll su tutta l'app e, se lo staff è in sessione,
/// mostra l'avviso e alla scadenza esegue il logout.
class StaffIdleGuard extends StatefulWidget {
  const StaffIdleGuard({super.key, required this.child});
  final Widget child;

  @override
  State<StaffIdleGuard> createState() => _StaffIdleGuardState();
}

class _StaffIdleGuardState extends State<StaffIdleGuard> {
  StaffIdleController? _controller;
  var _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    StaffIdleWatch.instance.addListener(_onWatch);
    if (StaffIdleWatch.instance.active) _arm();
  }

  @override
  void dispose() {
    StaffIdleWatch.instance.removeListener(_onWatch);
    _controller?.dispose();
    super.dispose();
  }

  void _onWatch() {
    if (StaffIdleWatch.instance.active) {
      _arm();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  void _arm() {
    _controller?.dispose();
    _controller = StaffIdleController(onWarn: _showWarn, onLogout: _timeoutLogout)..start();
  }

  void _ping() {
    if (!StaffIdleWatch.instance.active) return;
    if (_dialogOpen) return;
    _controller?.ping();
  }

  void _stay() {
    _dialogOpen = false;
    _controller?.ping();
  }

  void _showWarn() {
    if (!mounted || !StaffIdleWatch.instance.active || _dialogOpen) return;
    final nav = farmaciaNavigatorKey.currentState;
    if (nav == null) return;
    _dialogOpen = true;
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Sei ancora lì?'),
        content: const Text('Per sicurezza verrai disconnesso tra 2 minuti per inattività.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              _stay();
            },
            child: const Text('Resta connesso'),
          ),
        ],
      ),
    ).whenComplete(() {
      _dialogOpen = false;
    });
  }

  Future<void> _timeoutLogout() async {
    if (!StaffIdleWatch.instance.active) return;
    StaffIdleWatch.instance.deactivate();
    final nav = farmaciaNavigatorKey.currentState;
    if (nav != null && _dialogOpen && nav.canPop()) {
      nav.pop();
    }
    _dialogOpen = false;
    await StaffAuth().signOut();
    nav?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RolePicker()), (_) => false);
    final ctx = farmaciaNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Disconnesso per inattività')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ping(),
      onPointerSignal: (_) => _ping(),
      child: widget.child,
    );
  }
}
