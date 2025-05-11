import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'tab_dashboard.dart';
import 'tab_volunteer_approval.dart';
import 'tab_reports.dart';
import 'tab_profile.dart';
import 'view_all_users.dart';
import 'server.dart';

// Application theme with black color scheme instead of blue
final ThemeData appTheme = ThemeData(
  primaryColor: Colors.black, // Changed from blue to black
  scaffoldBackgroundColor: Colors.white,
  cardColor: Colors.white,
  shadowColor: Colors.black.withOpacity(0.1),
  colorScheme: ColorScheme.light(
    primary: Colors.black, // Changed from blue to black
    secondary: Color(0xFF4CAF50),
    error: Color(0xFFE53935),
    background: Colors.white,
    surface: Colors.white,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black, // Changed from blue to black
    elevation: 0,
  ),
);

// Category colors for visual consistency
final Map<String, Color> categoryColors = {
  'users': Colors.black,     // Changed from blue to black
  'products': Color(0xFF4CAF50),  // Green
  'donations': Color(0xFFFF9800), // Orange
  'volunteers': Color(0xFF9C27B0),// Purple
  'reports': Color(0xFFE53935),   // Red
};

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _selectedIndex = 0;
  
  // Four tabs: Dashboard, Volunteer Requests, Reports, and Profile
  final List<Widget> _tabs = const [
    AdminDashboard(),
    VolunteerRequestsScreen(),
    ReportsTab(), 
    AdminProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    _verifyAuthCookie();
  }

  Future<void> _verifyAuthCookie() async {
    final authCookie = await _secureStorage.read(key: 'authCookie');
    if (authCookie == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final response = await http.get(
      Uri.parse('$serverUrl/api/me'),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie,
      },
    );
    if (response.statusCode != 200) {
      await _secureStorage.delete(key: 'authCookie');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _logout() async {
    // First, clear local storage and navigate
    final authCookie = await _secureStorage.read(key: 'authCookie');
    await _secureStorage.delete(key: 'authCookie');
    
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (route) => false,
      );
    }

    // Then, make the API call in the background
    if (authCookie != null) {
      try {
        await http.post(
          Uri.parse('$serverUrl/api/logout'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
      } catch (e) {
        print("Backend logout error: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: appTheme,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('𝒞𝒶𝓂𝓅𝓊𝓈𝒦𝒶𝓇𝓉', 
            style: TextStyle(fontWeight: FontWeight.bold)
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline), 
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllUsersScreen(),
                  ),
                );
              }
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _tabs[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black, // Changed from blue to black
          unselectedItemColor: Colors.grey,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() { _selectedIndex = index; }),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: "Dashboard",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.request_page),
              label: "Requests",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.report),
              label: "Reports",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: "Profile",
            ),
          ],
        ),
      ),
    );
  }
}
