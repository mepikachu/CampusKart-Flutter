import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'server.dart';
// Add these color constants to match tab_donations.dart
const outlineColor = Color(0xFFE1E3E6);
const textPrimaryColor = Color(0xFF202124);
const textSecondaryColor = Color(0xFF5F6368);

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
  bool _isLoading = true;
  String _errorMessage = '';

  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }

  Future<void> _fetchLeaderboard() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Check if user is blocked
      final userResponse = await http.get(
        Uri.parse('$serverUrl/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (userResponse.statusCode == 403) {
        final userData = json.decode(userResponse.body);
        _showBlockedDialog(
          blockedAt: userData['blockedAt'],
          reason: userData['blockedReason'],
        );
        return;
      }

      // Continue with existing leaderboard fetch
      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/leaderboard'),
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
          _isLoading = false;
        });
      } else {
        throw Exception(data['error'] ?? 'Failed to load leaderboard');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showBlockedDialog({String? blockedAt, String? reason}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block_rounded,
                  size: 48,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Volunteer Access Blocked',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your volunteer access has been suspended by the administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reason != null) ...[
                      Text(
                        'Reason:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reason,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (blockedAt != null) ...[
                      Text(
                        'Blocked on:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(blockedAt),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Please contact the administrator to discuss further about restoring your volunteer access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _secureStorage.delete(key: 'authCookie');
                    if (mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/login',
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
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
            color: textPrimaryColor,
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
                hasData ? (user['userName'] ?? 'Unknown') : '-----',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: hasData ? textPrimaryColor : Colors.grey,
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
    if (_isLoading) {
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