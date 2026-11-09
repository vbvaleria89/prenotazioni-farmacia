import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/role_picker.dart';
import 'services/booking_service.dart';
import 'services/calendar_service.dart';
import 'services/customer_auth.dart';
export 'services/customer_auth.dart' show customerAuth, CustomerAuth, PersonalSession;
import 'services/staff_auth.dart';
import 'services/google_calendar_service.dart';
import 'theme/brand.dart';

final googleCalendar = GoogleCalendarService(fallback: MockCalendarService());
final bookingService = BookingService(calendar: googleCalendar);
final staffAuth = StaffAuth();

class FarmaciaApp extends StatelessWidget {
  const FarmaciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('it'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: Brand.theme(),
      home: const RolePicker(),
    );
  }
}
