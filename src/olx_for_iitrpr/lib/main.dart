import 'package:flutter/material.dart';

import 'login/login.dart';
import 'login/sign_up.dart';
import 'login/forgot_password.dart';

import 'user/home.dart';
import 'admin/home.dart';
import 'volunteer/home.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusKart',
      debugShowCheckedModeBanner: false,
      routes: {
        '/user_home': (context) => const UserHomeScreen(),
        '/admin_home': (context) => const AdminHomeScreen(),
        '/volunteer_home': (context) => const VolunteerHomeScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/login': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
          return LoginScreen(errorMessage: args?['errorMessage']);
        },
      },
      home: const LoginScreen(),
      theme: ThemeData(
        primaryColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black, // This makes the text and icons black
          elevation: 1, // Subtle shadow
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}
