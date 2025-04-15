import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'view_profile.dart';

class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({Key? key}) : super(key: key);

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen> {
  final _secureStorage = const FlutterSecureStorage();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';

  // Search & Filter variables
  final TextEditingController _searchController = TextEditingController();
  String _selectedRole = 'All';
  String _selectedStatus = 'All';
  String _sortBy = 'userName';
  bool _sortAscending = true;

  final List<String> _roleOptions = ['All', 'admin', 'volunteer', 'volunteer_pending', 'user'];
  final List<String> _statusOptions = ['All', 'Blocked', 'Active'];
  final Map<String, String> _sortOptions = {
    'userName': 'Username',
    'email': 'Email',
    'role': 'Role',
    'registrationDate': 'Registration Date'
  };

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/users/'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<UserModel> users = [];
          for (var user in data['users']) {
            users.add(UserModel.fromJson(user));
          }
          setState(() {
            _allUsers = users;
            _applyFiltersAndSort();
            _isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load users');
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _toggleBlockStatus(UserModel user) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Create a reason controller for the dialog
      final TextEditingController reasonController = TextEditingController();
      reasonController.text = 'Blocked by administrator';
      
      // If blocking, show dialog to get reason
      String blockReason = 'Blocked by administrator';
      if (!user.isBlocked) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Block ${user.userName}?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please provide a reason for blocking this user:'),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Reason for blocking',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  blockReason = reasonController.text;
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('BLOCK'),
              ),
            ],
          ),
        );
      }
      
      // Prepare the request body based on whether we're blocking or unblocking
      final Map<String, dynamic> requestBody = {
        'action': user.isBlocked ? 'unblock' : 'block',
        // Include reason if blocking
        if (!user.isBlocked) 'blockReason': blockReason
      };
      
      final response = await http.patch(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/users/${user.id}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(user.isBlocked 
                  ? 'User ${user.userName} has been unblocked' 
                  : 'User ${user.userName} has been blocked'),
              backgroundColor: user.isBlocked ? Colors.green : Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh user list
          _fetchUsers();
        } else {
          throw Exception(data['message'] ?? 'Failed to update user');
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyFiltersAndSort() {
    List<UserModel> filtered = List.from(_allUsers);
    
    // Apply role filter
    if (_selectedRole != 'All') {
      filtered = filtered.where((user) => user.role == _selectedRole).toList();
    }
    
    // Apply status filter
    if (_selectedStatus != 'All') {
      filtered = filtered.where((user) => 
        (_selectedStatus == 'Blocked') == user.isBlocked).toList();
    }
    
    // Apply search
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((user) => 
        user.userName.toLowerCase().contains(query) || 
        user.email.toLowerCase().contains(query)).toList();
    }
    
    // Apply sorting
    filtered.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'userName':
          result = a.userName.toLowerCase().compareTo(b.userName.toLowerCase());
          break;
        case 'email':
          result = a.email.toLowerCase().compareTo(b.email.toLowerCase());
          break;
        case 'role':
          result = a.role.compareTo(b.role);
          break;
        case 'registrationDate':
          result = a.registrationDate.compareTo(b.registrationDate);
          break;
        default:
          result = a.userName.toLowerCase().compareTo(b.userName.toLowerCase());
      }
      return _sortAscending ? result : -result;
    });
    
    setState(() {
      _filteredUsers = filtered;
    });
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter Users',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              
              // Role Filter
              const Text('Role', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _roleOptions.map((role) => FilterChip(
                  label: Text(role),
                  selected: _selectedRole == role,
                  onSelected: (selected) {
                    setModalState(() {
                      _selectedRole = selected ? role : 'All';
                    });
                  },
                )).toList(),
              ),
              
              const SizedBox(height: 16),
              
              // Status Filter
              const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _statusOptions.map((status) => FilterChip(
                  label: Text(status),
                  selected: _selectedStatus == status,
                  onSelected: (selected) {
                    setModalState(() {
                      _selectedStatus = selected ? status : 'All';
                    });
                  },
                )).toList(),
              ),
              
              const SizedBox(height: 24),
              
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      setModalState(() {
                        _selectedRole = 'All';
                        _selectedStatus = 'All';
                      });
                    },
                    child: const Text('Reset Filters'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _applyFiltersAndSort();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort By'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _sortOptions.entries.map((entry) => 
            RadioListTile<String>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: _sortBy,
              onChanged: (value) {
                setState(() {
                  if (_sortBy == value) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = value!;
                    _sortAscending = true;
                  }
                });
                Navigator.pop(context);
                _applyFiltersAndSort();
              },
              secondary: _sortBy == entry.key 
                ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward) 
                : null,
            ),
          ).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('All Users', style: TextStyle(color: Colors.black)),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.blue, size: 20),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Search and Filter Bar - Made more compact
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                // Search Field with rounded corners and compact design
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by username or email',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    isDense: true,
                    suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                            });
                            _applyFiltersAndSort();
                          },
                        )
                      : null,
                  ),
                  onChanged: (value) {
                    _applyFiltersAndSort();
                  },
                ),
                
                const SizedBox(height: 8),
                
                // Filter and Sort Buttons in a more compact row
                Row(
                  children: [
                    // Filter Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showFilterDialog,
                        icon: const Icon(Icons.filter_list, size: 16),
                        label: const Text('Filter'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sort Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showSortDialog,
                        icon: const Icon(Icons.sort, size: 16),
                        label: Text(_sortOptions[_sortBy] ?? 'Sort'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Active Filters Chips - made more compact and horizontal scrollable
                if (_selectedRole != 'All' || _selectedStatus != 'All')
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (_selectedRole != 'All')
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Chip(
                              label: Text('Role: $_selectedRole'),
                              labelStyle: const TextStyle(fontSize: 12),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onDeleted: () {
                                setState(() {
                                  _selectedRole = 'All';
                                });
                                _applyFiltersAndSort();
                              },
                            ),
                          ),
                        if (_selectedStatus != 'All')
                          Chip(
                            label: Text('Status: $_selectedStatus'),
                            labelStyle: const TextStyle(fontSize: 12),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            onDeleted: () {
                              setState(() {
                                _selectedStatus = 'All';
                              });
                              _applyFiltersAndSort();
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          // Divider
          const Divider(height: 1),
          
          // User List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isError
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 60, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Error: $_errorMessage'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchUsers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredUsers.isEmpty
                        ? const Center(
                            child: Text('No users found'),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchUsers,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _filteredUsers.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                return _buildUserCard(user);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserCard(UserModel user) {
    final roleColor = _getRoleColor(user.role);
    
    // More compact card design
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdminProfileView(userId: user.id),
        ),
      ).then((_) => _fetchUsers()), // Refresh when returning from profile
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // User Avatar with initial
            CircleAvatar(
              radius: 22,
              backgroundColor: user.isBlocked 
                ? Colors.grey[300] 
                : roleColor.withOpacity(0.1),
              child: Text(
                user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: user.isBlocked ? Colors.grey[600] : roleColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // User Details Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Username and Role in the same row
                  Row(
                    children: [
                      Text(
                        user.userName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          decoration: user.isBlocked ? TextDecoration.lineThrough : null,
                          color: user.isBlocked ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: roleColor,
                          ),
                        ),
                      ),
                      if (user.isBlocked) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.block, color: Colors.red[400], size: 14),
                      ],
                    ],
                  ),
                  
                  // Email
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 13,
                      color: user.isBlocked ? Colors.grey[500] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Block/Unblock Button - made smaller and more subtle
            IconButton(
              onPressed: () => _toggleBlockStatus(user),
              icon: Icon(
                user.isBlocked ? Icons.lock_open : Icons.block,
                size: 18,
              ),
              style: IconButton.styleFrom(
                foregroundColor: user.isBlocked ? Colors.green : Colors.red,
                backgroundColor: user.isBlocked 
                    ? Colors.green.withOpacity(0.1) 
                    : Colors.red.withOpacity(0.1),
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(32, 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'volunteer':
        return Colors.green;
      case 'volunteer_pending':
        return Colors.amber;
      case 'user':
      default:
        return Colors.blue;
    }
  }
}

class UserModel {
  final String id;
  final String userName;
  final String email;
  final String role;
  final bool isBlocked;
  final DateTime registrationDate;
  final String? blockedReason;
  final DateTime? blockedAt;

  UserModel({
    required this.id,
    required this.userName,
    required this.email,
    required this.role,
    required this.isBlocked,
    required this.registrationDate,
    this.blockedReason,
    this.blockedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? '',
      userName: json['userName'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      isBlocked: json['isBlocked'] ?? false,
      registrationDate: json['registrationDate'] != null 
          ? DateTime.parse(json['registrationDate']) 
          : DateTime.now(),
      blockedReason: json['blockedReason'],
      blockedAt: json['blockedAt'] != null 
          ? DateTime.parse(json['blockedAt']) 
          : null,
    );
  }
}
