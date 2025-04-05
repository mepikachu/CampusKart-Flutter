import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'tab_dashboard.dart';
import 'tab_volunteer_approval.dart';
import 'tab_reports.dart'; // Add this import
import 'tab_profile.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _selectedIndex = 0;
  
  // Four tabs: Dashboard, Volunteer Requests, Reports, and Profile
  final List _tabs = const [
    AdminDashboard(),
    VolunteerRequestsScreen(),
    ReportsTab(), // Add the reports tab
    AdminProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    _verifyAuthCookie();
  }

  Future _verifyAuthCookie() async {
    final authCookie = await _secureStorage.read(key: 'authCookie');
    if (authCookie == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final response = await http.get(
      Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OLX-IITRPR"),
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Required for more than 3 items
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
          BottomNavigationBarItem( // Add reports tab item
            icon: Icon(Icons.report),
            label: "Reports",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
