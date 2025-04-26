import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';
import 'home.dart';
import 'server.dart';

class ViewProfileScreen extends StatefulWidget {
  final String userId;
  
  const ViewProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? userData;
  List<dynamic> userDonations = [];
  String currentUserId = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserInfo().then((_) {
      // Check if viewing own profile, redirect to tab_profile if so
      if (currentUserId == widget.userId) {
        // Navigate to tab_profile and remove this screen from stack
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pop(context);
          UserHomeScreen.homeKey.currentState?.switchToTab(1);
        });
      } else {
        _fetchUserProfile();
      }
    });
  }

  Future<void> _loadCurrentUserInfo() async {
    try {
      final userId = await _secureStorage.read(key: 'userId');
      if (userId != null) {
        setState(() {
          currentUserId = userId;
        });
      }
    } catch (e) {
      print('Error loading user info: $e');
    }
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      isLoading = true;
      isError = false;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/profile/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            userData = data['user'];
            userDonations = data['donations'] ?? [];
            isLoading = false;
          });
          
          // Load profile picture if available
          if (userData != null && (userData!['profilePicture'] == true || 
              (userData!['profilePicture'] is Map && userData!['profilePicture']['data'] != null))) {
            _loadProfilePicture();
          }
        } else {
          setState(() {
            isLoading = false;
            isError = true;
            errorMessage = data['error'] ?? 'Failed to load user profile';
          });
        }
      } else {
        setState(() {
          isLoading = false;
          isError = true;
          errorMessage = 'Failed to load user profile. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMessage = 'Error: $e';
      });
      print('Error fetching profile: $e');
    }
  }

  Future<void> _loadProfilePicture() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/profile-picture/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        if (response.headers['content-type']?.contains('application/json') != true) {
          // This is binary data (image)
          if (mounted) {
            setState(() {
              if (userData != null) {
                userData!['profilePictureData'] = base64Encode(response.bodyBytes);
              }
            });
          }
        }
      }
    } catch (e) {
      print('Error loading profile picture: $e');
    }
  }

  // Method to open chat with this user
  Future<void> _messageUser() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.userId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Navigate to chat screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: data['conversation']['_id'],
                partnerNames: userData?['userName'] ?? 'User',
                partnerId: widget.userId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Failed to start conversation')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(userData != null ? userData!['userName'] ?? 'User Profile' : 'User Profile'),
        elevation: 2,
      ),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator())
          : isError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(errorMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchUserProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildUserProfileContent(),
    );
  }

  Widget _buildUserProfileContent() {
    if (userData == null) {
      return const Center(child: Text('No user data available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Header with Picture
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: userData!['profilePictureData'] != null
                      ? MemoryImage(base64Decode(userData!['profilePictureData']))
                      : null,
                  child: userData!['profilePictureData'] == null
                      ? const Icon(Icons.person, size: 60, color: Colors.grey)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  userData!['userName'] ?? 'Unknown User',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(userData!['role']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    userData!['role']?.toUpperCase() ?? 'USER',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Member since ${_formatDate(userData!['registrationDate'])}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                // Message Button - New addition
                ElevatedButton.icon(
                  onPressed: _messageUser,
                  icon: const Icon(Icons.message),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          
          // Only show personal contact info if viewing own profile
          if (currentUserId == widget.userId) ...[
            const SizedBox(height: 16),
            const Text(
              'Contact Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            if (userData!['email'] != null)
              _buildInfoItem(Icons.email_outlined, 'Email', userData!['email']),
            
            if (userData!['phone'] != null)
              _buildInfoItem(Icons.phone_outlined, 'Phone', userData!['phone']),
          ],
          
          // Address information (visible to everyone)
          if (userData!['address'] != null) ...[
            if (currentUserId != widget.userId) ...[
              const SizedBox(height: 16),
              const Text(
                'Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ],
            _buildAddressSection(userData!['address']),
          ],
          
          const SizedBox(height: 24),
          const Divider(),
          
          // Donations Section
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Donations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${userDonations.length} items',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          userDonations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.volunteer_activism_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No donations yet',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: userDonations.length,
                  itemBuilder: (context, index) => _buildDonationItem(userDonations[index]),
                ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection(Map<String, dynamic> address) {
    final street = address['street'];
    final city = address['city'];
    final state = address['state'];
    final zipCode = address['zipCode'];
    final country = address['country'];
    
    final formattedAddress = [
      if (street != null && street.isNotEmpty) street,
      if (city != null && city.isNotEmpty) city,
      if (state != null && state.isNotEmpty) state,
      if (zipCode != null && zipCode.isNotEmpty) zipCode,
      if (country != null && country.isNotEmpty) country,
    ].join(', ');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Address',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedAddress.isNotEmpty ? formattedAddress : 'No address provided',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationItem(Map<String, dynamic> donation) {
    final status = donation['status'] ?? 'available';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.volunteer_activism,
                size: 30,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    donation['name'] ?? 'Unnamed Donation',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    donation['description'] ?? 'No description',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDate(donation['donationDate']),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'available' ? Colors.green.shade100 : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: status == 'available' ? Colors.green.shade800 : Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.red.shade700;
      case 'volunteer':
        return Colors.green.shade700;
      case 'volunteer_pending':
        return Colors.orange.shade700;
      default:
        return Colors.blue.shade700;
    }
  }
}
