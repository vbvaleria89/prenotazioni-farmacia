import 'package:flutter/material.dart';
import '../models/personal_role.dart';
import '../services/customer_auth.dart';
import '../theme/brand.dart';
import 'client/my_bookings.dart';
import 'staff/staff_hub.dart';
import 'client/services_home.dart';

/// Home pubblica. Se il cliente è già connesso, va alle sue prenotazioni senza il form.
class RolePicker extends StatefulWidget {
  const RolePicker({super.key});
  @override
  State<RolePicker> createState() => _RolePickerState();
}

class _RolePickerState extends State<RolePicker> {
  var _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _resume() async {
    try {
      final user = await customerAuth.restoredUser();
      if (!mounted) return;
      if (user != null && !user.isAnonymous) {
        final session = await customerAuth.sessionForCurrentUser();
        if (!mounted) return;
        if (session.role == PersonalRole.staff && session.employee != null) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => StaffHub(employee: session.employee!)), (route) => false);
          return;
        }
        if (session.role == PersonalRole.customer) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MyBookings()), (route) => false);
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Brand.primary)),
      );
    }
    return const ServicesHome();
  }
}
