import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VolunteerHomePage extends StatefulWidget {
  const VolunteerHomePage({Key? key}) : super(key: key);

  @override
  State<VolunteerHomePage> createState() => _VolunteerHomePageState();
}

class _VolunteerHomePageState extends State<VolunteerHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Volunteer Home'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Leaderboard'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          // Replace this with your actual dashboard widget if needed.
          Center(child: Text("Dashboard Content")),
          VolunteerLeaderboardTab(),
        ],
      ),
    );
  }
}

class VolunteerLeaderboardTab extends StatefulWidget {
  const VolunteerLeaderboardTab({Key? key}) : super(key: key);

  @override
  State<VolunteerLeaderboardTab> createState() => _VolunteerLeaderboardTabState();
}

class _VolunteerLeaderboardTabState extends State<VolunteerLeaderboardTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> _donorsLeaderboard = [];
  List<dynamic> _volunteersLeaderboard = [];
  bool _isLoadingLeaderboard = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations/leaderboard'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _donorsLeaderboard = data['donors'];
          _volunteersLeaderboard = data['volunteers'];
          _isLoadingLeaderboard = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Error fetching leaderboard';
          _isLoadingLeaderboard = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingLeaderboard = false;
      });
    }
  }

  Widget _buildLeaderboardSection(String title, List<dynamic> leaderboard, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 16),
        ...List.generate(5, (index) {
          final bool hasData = index < leaderboard.length;
          final user = hasData ? leaderboard[index] : null;
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[300],
                child: hasData && user != null && user['userName'] != null
                    ? Text(user['userName'][0].toUpperCase())
                    : const Icon(Icons.person),
              ),
              title: Text(
                hasData && user != null && user['userName'] != null ? user['userName'] : 'Anonymous',
                style: const TextStyle(fontSize: 16, color: Colors.black),
              ),
              trailing: hasData && user != null && user['totalDonations'] != null
                  ? Text('${user['totalDonations']}', style: TextStyle(fontSize: 16, color: color))
                  : const Text('0'),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLeaderboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildLeaderboardSection('Top Donors', _donorsLeaderboard, Colors.blue[700]!),
        const SizedBox(height: 24),
        _buildLeaderboardSection('Top Volunteers', _volunteersLeaderboard, Colors.green[700]!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLeaderboard) {
      return const Center(child: CircularProgressIndicator());
    } else if (_errorMessage.isNotEmpty) {
      return Center(child: Text('Error: $_errorMessage'));
    }
    return RefreshIndicator(
      onRefresh: _fetchLeaderboard,
      child: _buildLeaderboard(),
    );
  }
}