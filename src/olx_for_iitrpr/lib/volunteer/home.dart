import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'tab_donations.dart';
import 'tab_leaderboard.dart';
import 'tab_profile.dart';
import 'chat_list.dart';
import 'server.dart';
class VolunteerHomeScreen extends StatefulWidget {
  const VolunteerHomeScreen({super.key});

  @override
  State<VolunteerHomeScreen> createState() => _VolunteerHomeScreenState();
}

class _VolunteerHomeScreenState extends State<VolunteerHomeScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _selectedIndex = 0;

  // Three tabs: Donations, Leaderboard, and Profile
  final List<Widget> _tabs = [
    const VolunteerDonationsPage(),
    const VolunteerLeaderboardTab(),
    const VolunteerProfileTab(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "𝒞𝒶𝓂𝓅𝓊𝓈𝒦𝒶𝓇𝓉",
          style: TextStyle(color: Colors.black87),
        ),
        centerTitle: false, // This aligns the title to the left
        actions: [
          IconButton(
            icon: const Icon(
              Icons.chat_bubble,
              color: Colors.black87,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() { 
          _selectedIndex = index; 
        }),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.volunteer_activism),
            label: "Donations",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: "Leaderboard",
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