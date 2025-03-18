import 'package:flutter/material.dart';
import 'chats.dart';
import 'products_tab.dart';
import 'sell_tab.dart';
import 'donations_tab.dart';
import 'profile_tab.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<UserHomeScreen> {
  int _selectedIndex = 0;

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
