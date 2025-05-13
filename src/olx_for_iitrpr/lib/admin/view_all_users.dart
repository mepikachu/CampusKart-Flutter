import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'view_profile.dart';
import 'server.dart';

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
  bool _isFilterExpanded = false;

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
        Uri.parse('$serverUrl/api/admin/users/'),
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
      
      if (!user.isBlocked) {
        // Show dialog for block reason
        final TextEditingController reasonController = TextEditingController();
        reasonController.text = 'Blocked by administrator';
        
        final bool? shouldBlock = await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.block, color: Colors.red.shade700),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Block User',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.userName,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Reason for blocking:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.red.shade300),
                      ),
                      hintText: 'Enter reason for blocking',
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'CANCEL',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('BLOCK USER'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        if (shouldBlock != true) return;

        // Make block request
        final response = await http.post(
          Uri.parse('$serverUrl/api/admin/users/${user.id}/block'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
          body: json.encode({
            'reason': reasonController.text,
          }),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('User ${user.userName} has been blocked'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _fetchUsers();
          } else {
            throw Exception(data['message'] ?? 'Failed to block user');
          }
        } else {
          throw Exception('Server returned ${response.statusCode}');
        }
      } else {
        // Show unblock confirmation dialog
        final bool? shouldUnblock = await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_open, color: Colors.green.shade700),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unblock User',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.userName,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Are you sure you want to unblock this user? They will regain access to all platform features.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'CANCEL',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('UNBLOCK USER'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        if (shouldUnblock != true) return;

        // Make unblock request
        final response = await http.post(
          Uri.parse('$serverUrl/api/admin/users/${user.id}/unblock'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('User ${user.userName} has been unblocked'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _fetchUsers();
          } else {
            throw Exception(data['message'] ?? 'Failed to unblock user');
          }
        } else {
          throw Exception('Server returned ${response.statusCode}');
        }
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
        title: const Text('All Users'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {});
                _filterUsers();
              },
              decoration: InputDecoration(
                hintText: 'Search users by name or email',
                prefixIcon: const Icon(Icons.search, size: 22),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: const Color(0xFF1A73E8)),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),

          // Filter section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter button is full width
                InkWell(
                  onTap: () {
                    setState(() {
                      _isFilterExpanded = !_isFilterExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _hasActiveFilters() ? const Color(0xFF1A73E8).withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hasActiveFilters() ? const Color(0xFF1A73E8) : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list,
                          size: 16,
                          color: _hasActiveFilters() ? const Color(0xFF1A73E8) : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Filters',
                          style: TextStyle(
                            color: _hasActiveFilters() ? const Color(0xFF1A73E8) : Colors.grey.shade700,
                            fontWeight: _hasActiveFilters() ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (_hasActiveFilters())
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              _getActiveFilterCount().toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (_hasActiveFilters())
                          TextButton(
                            onPressed: _clearFilters,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: const Color(0xFF1A73E8),
                            ),
                            child: const Text('Clear All', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),

                // Active filter chips
                if (_hasActiveFilters())
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_selectedRole != 'All')
                            _buildActiveFilterChip('Role: $_selectedRole', () {
                              setState(() {
                                _selectedRole = 'All';
                              });
                              _filterUsers();
                            }),
                          if (_selectedStatus != 'All')
                            _buildActiveFilterChip('Status: $_selectedStatus', () {
                              setState(() {
                                _selectedStatus = 'All';
                              });
                              _filterUsers();
                            }),
                          if (_sortBy != 'userName')
                            _buildActiveFilterChip('Sort: ${_sortOptions[_sortBy]}', () {
                              setState(() {
                                _sortBy = 'userName';
                              });
                              _filterUsers();
                            }),
                        ],
                      ),
                    ),
                  ),

                // Expanded filter options
                if (_isFilterExpanded)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role filters
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Role',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    'All',
                                    'admin',
                                    'volunteer',
                                    'volunteer_pending',
                                    'user',
                                  ].map((role) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildFilterOptionChip(
                                      role,
                                      _selectedRole == role,
                                      () {
                                        setState(() => _selectedRole = role);
                                        _filterUsers();
                                      },
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 16),
                        // Status filters
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    'All',
                                    'Active',
                                    'Blocked',
                                  ].map((status) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildFilterOptionChip(
                                      status,
                                      _selectedStatus == status,
                                      () {
                                        setState(() => _selectedStatus = status);
                                        _filterUsers();
                                      },
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 16),
                        // Sort options
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sort By',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _sortOptions.entries.map((entry) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildFilterOptionChip(
                                      entry.value,
                                      _sortBy == entry.key,
                                      () {
                                        setState(() {
                                          if (_sortBy == entry.key) {
                                            _sortAscending = !_sortAscending;
                                          } else {
                                            _sortBy = entry.key;
                                            _sortAscending = true;
                                          }
                                        });
                                        _filterUsers();
                                      },
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Results counter
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4, left: 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Showing ${_filteredUsers.length} user${_filteredUsers.length != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                
                const Divider(height: 1),
              ],
            ),
          ),

          // Users list
          Expanded(
            child: _isLoading
              ? _buildLoadingList()
              : _errorMessage.isNotEmpty
                ? _buildErrorView()
                : _filteredUsers.isEmpty
                  ? _buildEmptyView()
                  : _buildUsersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChip(String label, VoidCallback onDelete) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A73E8).withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A73E8).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF1A73E8),
                fontWeight: FontWeight.w500,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: const Color(0xFF1A73E8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection(String title, List<String> options, String selected, Function(String) onSelect) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) => _buildFilterOptionChip(
              option,
              selected == option,
              () => onSelect(option),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOptionChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A73E8).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A73E8).withOpacity(0.5) : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? const Color(0xFF1A73E8) : Colors.grey.shade700,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sort By',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sortOptions.entries.map((entry) => _buildFilterOptionChip(
              entry.value,
              _sortBy == entry.key,
              () {
                setState(() {
                  if (_sortBy == entry.key) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = entry.key;
                    _sortAscending = true;
                  }
                });
                _filterUsers();
              },
            )).toList(),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedRole != 'All' || 
           _selectedStatus != 'All' || 
           _sortBy != 'userName';
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedRole != 'All') count++;
    if (_selectedStatus != 'All') count++;
    if (_sortBy != 'userName') count++;
    return count;
  }

  void _clearFilters() {
    setState(() {
      _selectedRole = 'All';
      _selectedStatus = 'All';
      _sortBy = 'userName';
      _sortAscending = true;
    });
    _filterUsers();
  }

  Future<void> _filterUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Filtering logic
      List<UserModel> filtered = _allUsers.where((user) {
        final matchesRole = _selectedRole == 'All' || user.role == _selectedRole;
        final matchesStatus = _selectedStatus == 'All' || 
                              (_selectedStatus == 'Active' && !user.isBlocked) || 
                              (_selectedStatus == 'Blocked' && user.isBlocked);
        return matchesRole && matchesStatus;
      }).toList();
      
      setState(() {
        _filteredUsers = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Widget _buildLoadingList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Skeleton avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              
              // Skeleton text column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Skeleton username
                    Container(
                      height: 16,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 4),
                    // Skeleton email
                    Container(
                      height: 14,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                    ),
                  ],
                ),
              ),
              
              // Skeleton button
              Container(
                height: 32,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorView() {
    return Center(
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
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Text(
        'No users found',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    return RefreshIndicator(
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
    );
  }
  
  Widget _buildUserCard(UserModel user) {
    final roleColor = _getRoleColor(user.role);
    
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ViewProfileScreen(userId: user.id),
        ),
      ).then((_) => _fetchUsers()),
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
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
            
            // Only show block/unblock button for non-admin users
            if (user.role != 'admin')
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
