import 'package:flutter/material.dart';
import 'package:smartan_fitness/views/login_page.dart';
import 'package:smartan_fitness/views/signup_page.dart';
import 'package:smartan_fitness/views/user_info_page.dart';
import 'package:smartan_fitness/views/gym_verification_page.dart';
import 'package:smartan_fitness/views/main_navigation.dart';
import 'themes/app_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/': (context) => const LoginPage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/gym-verification': (context) => const GymVerificationPage(),
        '/user-info': (context) => const UserInfoPage(),
        '/dashboard': (context) => const MainNavigation(),
      },
      title: 'Smartan Fitness',
      theme: AppTheme.lightTheme,
    );
  }
}
