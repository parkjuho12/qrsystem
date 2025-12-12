import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/qr_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/generate_payment_qr_for_payment_screen.dart';
import 'services/auth_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');

  // AuthService에서 세션 복원
  await AuthService.restoreSession();

  if (AuthService.isLoggedIn) {
    // 토큰 유효성 검증
    final isValid = await AuthService.validateToken();
    if (!isValid) {
      await AuthService.logout();
    }
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '경복대 출입증',
      theme: ThemeData(primarySwatch: Colors.blue),
      locale: Locale('ko'),
      supportedLocales: [Locale('ko')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routes: {
        '/login': (context) => const LoginScreen(),
        '/qr': (context) {
          final user = AuthService.user;
          if (user != null) {
            return QRScreen(
              userId:
                  user['employee_number']?.toString() ??
                  user['user_id']?.toString() ??
                  '',
              userName: user['name'] ?? '',
              affiliation: user['affiliation'] ?? '',
              profileImage: user['profile_image'] ?? '1.jpeg',
            );
          }
          return const LoginScreen();
        },
        '/payment': (context) {
          final user = AuthService.user;
          return PaymentScreen(userId: user?['user_id'].toString() ?? '');
        },
        '/menu': (context) => WeeklyMenuScreen(),
        '/generate_payment_qr':
            (context) => GeneratePaymentQrForPaymentScreen(qrData: ''),
      },
      home:
          AuthService.isLoggedIn
              ? Builder(
                builder: (context) {
                  final user = AuthService.user;
                  if (user != null) {
                    return QRScreen(
                      userId:
                          user['employee_number']?.toString() ??
                          user['user_id']?.toString() ??
                          '',
                      userName: user['name'] ?? '',
                      affiliation: user['affiliation'] ?? '',
                      profileImage: user['profile_image'] ?? '1.jpeg',
                    );
                  }
                  return const LoginScreen();
                },
              )
              : const LoginScreen(),
    );
  }
}
