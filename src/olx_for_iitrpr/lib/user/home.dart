import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chats.dart';
import 'tab_products.dart';
import 'tab_sell.dart';
import 'tab_donations.dart';
import 'tab_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<UserHomeScreen> {
  final _secureStorage = const FlutterSecureStorage();
  int _selectedIndex = 0;

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
    // Call /api/me to verify the cookie:
    final response = await http.get(
      Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie,
      },
    );
    if (response.statusCode != 200) {
      // Invalid cookie; clear it and redirect:
      await _secureStorage.delete(key: 'authCookie');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // List of four tabs displayed in the home screen.
  final List<Widget> _tabs = const [
    ProductsTab(),
    SellTab(),
    DonationsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "OLX-IITRPR",
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
        onTap: (index) => setState(() { _selectedIndex = index; }),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Products",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sell),
            label: "Sell",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.volunteer_activism),
            label: "Donations",
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
