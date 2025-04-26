import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'view_profile.dart';
import 'server.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final _secureStorage = const FlutterSecureStorage();
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  String? _selectedRole;
  String? _blockFilter;
  String? _sortBy;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      setState(() => _isLoading = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/users/'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        setState(() {
          _allUsers = data['users'].where((user) => user['role'] != 'admin').toList();
          _filteredUsers = List.from(_allUsers);
          _isLoading = false;
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to fetch users');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleUserBlock(String userId, bool currentBlockStatus) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/admin/users/$userId/${currentBlockStatus ? 'unblock' : 'block'}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        _fetchUsers(); // Refresh the list
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(currentBlockStatus ? 'User unblocked' : 'User blocked')),
        );
      } else {
        throw Exception(data['message'] ?? 'Action failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _filterUsers() {
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final matchesSearch = _searchQuery.isEmpty ||
            user['userName'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            user['email'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesRole = _selectedRole == null || user['role'] == _selectedRole;
        
        final matchesBlockStatus = _blockFilter == null ||
            (_blockFilter == 'blocked' && user['isBlocked'] == true) ||
            (_blockFilter == 'unblocked' && user['isBlocked'] != true);

        return matchesSearch && matchesRole && matchesBlockStatus;
      }).toList();

      if (_sortBy != null) {
        _filteredUsers.sort((a, b) {
          switch (_sortBy) {
            case 'name_asc':
              return a['userName'].toString().compareTo(b['userName'].toString());
            case 'name_desc':
              return b['userName'].toString().compareTo(a['userName'].toString());
            case 'recent':
              return DateTime.parse(b['registrationDate'] ?? '').compareTo(
                DateTime.parse(a['registrationDate'] ?? ''));
            case 'oldest':
              return DateTime.parse(a['registrationDate'] ?? '').compareTo(
                DateTime.parse(b['registrationDate'] ?? ''));
            default:
              return 0;
          }
        });
      }
    });
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'volunteer':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('All Users'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Search bar
                TextField(
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _filterUsers();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by username or email',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Filters row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Role filter
                      DropdownButton<String>(
                        value: _selectedRole,
                        hint: const Text('Filter by role'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All roles')),
                          const DropdownMenuItem(value: 'user', child: Text('Users')),
                          const DropdownMenuItem(value: 'volunteer', child: Text('Volunteers')),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedRole = value);
                          _filterUsers();
                        },
                      ),
                      const SizedBox(width: 16),
                      
                      // Block status filter
                      DropdownButton<String>(
                        value: _blockFilter,
                        hint: const Text('Filter by status'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All status')),
                          const DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                          const DropdownMenuItem(value: 'unblocked', child: Text('Active')),
                        ],
                        onChanged: (value) {
                          setState(() => _blockFilter = value);
                          _filterUsers();
                        },
                      ),
                      const SizedBox(width: 16),
                      
                      // Sort options
                      DropdownButton<String>(
                        value: _sortBy,
                        hint: const Text('Sort by'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Default')),
                          const DropdownMenuItem(value: 'name_asc', child: Text('Name (A-Z)')),
                          const DropdownMenuItem(value: 'name_desc', child: Text('Name (Z-A)')),
                          const DropdownMenuItem(value: 'recent', child: Text('Newest first')),
                          const DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                        ],
                        onChanged: (value) {
                          setState(() => _sortBy = value);
                          _filterUsers();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? _buildLoadingList()
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _filteredUsers.isEmpty
                        ? const Center(child: Text('No users found'))
                        : ListView.builder(
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              final role = user['role'] ?? 'user';
                              final isBlocked = user['isBlocked'] == true;
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: Colors.grey[200],
                                    backgroundImage: user['profilePicture'] != null &&
                                                   user['profilePicture'] is Map &&
                                                   user['profilePicture']['data'] != null
                                        ? MemoryImage(base64Decode(user['profilePicture']['data']))
                                        : null,
                                    child: (user['profilePicture'] == null ||
                                           !(user['profilePicture'] is Map) ||
                                           user['profilePicture']['data'] == null)
                                        ? Text(
                                            user['userName']?[0].toUpperCase() ?? '?',
                                            style: TextStyle(
                                              color: _getRoleColor(role),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    user['userName'] ?? 'Unknown User',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(user['email'] ?? 'No email'),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getRoleColor(role).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              role.toUpperCase(),
                                              style: TextStyle(
                                                color: _getRoleColor(role),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isBlocked 
                                                  ? Colors.red.withOpacity(0.1)
                                                  : Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              isBlocked ? 'BLOCKED' : 'ACTIVE',
                                              style: TextStyle(
                                                color: isBlocked ? Colors.red : Colors.green,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      isBlocked ? Icons.lock_open : Icons.block,
                                      color: isBlocked ? Colors.green : Colors.red,
                                    ),
                                    onPressed: () => _toggleUserBlock(user['_id'], isBlocked),
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AdminProfileView(
                                          userId: user['_id'],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingList() {
    return ListView.builder(
      itemCount: 10,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: const CircleAvatar(radius: 25),
              title: Container(
                width: double.infinity,
                height: 16,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 12,
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 8),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
