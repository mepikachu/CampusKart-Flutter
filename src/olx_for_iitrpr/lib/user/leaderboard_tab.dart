import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'view_profile.dart';

class LeaderboardTab extends StatefulWidget {
  const LeaderboardTab({super.key});

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isLoadingLeaderboard = true;
  List<dynamic> _donorsLeaderboard = [];
  List<dynamic> _volunteersLeaderboard = [];
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
        throw Exception(data['error'] ?? 'Failed to load leaderboard');
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
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF202124),
          ),
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
              onTap: hasData ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewProfileScreen(userId: user['_id']),
                  ),
                );
              } : null,
              leading: CircleAvatar(
                backgroundColor: hasData ? color.withOpacity(0.2) : Colors.grey[200],
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: hasData ? color : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                hasData ? (user['userName'] ?? 'Unknown') : '--------------',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: hasData ? const Color(0xFF202124) : Colors.grey,
                ),
              ),
              trailing: hasData
                  ? Text(
                      '${user['totalDonations']} ${title == 'Top Donors' ? 'donations' : 'collected'}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      '0 ${title == 'Top Donors' ? 'donations' : 'collected'}',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLeaderboard) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(child: Text('Error: $_errorMessage'));
    }

    return RefreshIndicator(
      onRefresh: _fetchLeaderboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLeaderboardSection('Top Donors', _donorsLeaderboard, Colors.blue[700]!),
          const SizedBox(height: 24),
          _buildLeaderboardSection('Top Volunteers', _volunteersLeaderboard, Colors.green[700]!),
        ],
      ),
    );
  }
}
