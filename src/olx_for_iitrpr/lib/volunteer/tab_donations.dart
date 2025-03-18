import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SortOption {
  nameAsc,
  nameDesc,
  dateAsc,
  dateDesc,
}

class VolunteerDonationsPage extends StatefulWidget {
  const VolunteerDonationsPage({super.key});

  @override
  State<VolunteerDonationsPage> createState() => _VolunteerDonationsPageState();
}

class _VolunteerDonationsPageState extends State<VolunteerDonationsPage> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> donations = [];
  List<dynamic> filteredDonations = [];
  String searchQuery = '';
  bool isLoading = true;
  String errorMessage = '';
  SortOption _currentSort = SortOption.dateDesc;

  @override
  void initState() {
    super.initState();
    fetchDonations();
  }

  Future<void> fetchDonations() async {
    try {
      setState(() => isLoading = true);
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          donations = data['donations'];
          filteredDonations = List.from(donations);
          _sortDonations();
          errorMessage = '';
        });
      } else {
        throw Exception(data['error'] ?? 'Failed to load donations');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _collectDonation(String donationId) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/donations/$donationId/collect'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donation collected successfully')),
        );
        fetchDonations(); // Refresh the list
      } else {
        throw Exception(data['error'] ?? 'Failed to collect donation');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _filterDonations(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      if (searchQuery.isEmpty) {
        filteredDonations = List.from(donations);
      } else {
        filteredDonations = donations.where((donation) {
          final name = donation['name']?.toString().toLowerCase() ?? '';
          final description = donation['description']?.toString().toLowerCase() ?? '';
          return name.contains(searchQuery) || description.contains(searchQuery);
        }).toList();
      }
      _sortDonations();
    });
  }

  void _sortDonations() {
    setState(() {
      filteredDonations.sort((a, b) {
        switch (_currentSort) {
          case SortOption.nameAsc:
            return (a['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase());
          case SortOption.nameDesc:
            return (b['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((a['name'] ?? '').toString().toLowerCase());
          case SortOption.dateDesc:
            return (b['createdAt'] ?? '').toString()
                .compareTo((a['createdAt'] ?? '').toString());
          case SortOption.dateAsc:
            return (a['createdAt'] ?? '').toString()
                .compareTo((b['createdAt'] ?? '').toString());
        }
      });
    });
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Sort by'),
                subtitle: const Text('Choose sorting option'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (A to Z)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameAsc;
                    _sortDonations();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Name (Z to A)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.nameDesc;
                    _sortDonations();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Newest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateDesc;
                    _sortDonations();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Date (Oldest First)'),
                onTap: () {
                  setState(() {
                    _currentSort = SortOption.dateAsc;
                    _sortDonations();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDonationCard(dynamic donation, int index) {
    Widget imageWidget;
    final List<dynamic> images = donation['images'] ?? [];

    if (images.isNotEmpty && images[0]['data'] != null) {
      try {
        final bytes = base64Decode(images[0]['data']);
        imageWidget = Image.memory(bytes, fit: BoxFit.cover);
      } catch (e) {
        imageWidget = Container(
          color: Colors.grey[300],
          child: const Center(child: Text('Error loading image')),
        );
      }
    } else {
      imageWidget = Container(
        color: Colors.grey[300],
        child: const Center(child: Text('No image')),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: imageWidget,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  donation['name'] ?? 'Donation ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  donation['status'] ?? 'Available',
                  style: const TextStyle(color: Colors.green),
                ),
                ElevatedButton(
                  onPressed: () => _collectDonation(donation['_id']),
                  child: const Text('Collect'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Filter Bar
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search donations...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: _filterDonations,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: () => _showSortMenu(context),
                tooltip: 'Sort donations',
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage.isNotEmpty
                  ? Center(child: Text('Error: $errorMessage'))
                  : RefreshIndicator(
                      onRefresh: fetchDonations,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: filteredDonations.length,
                        itemBuilder: (context, index) => _buildDonationCard(filteredDonations[index], index),
                      ),
                    ),
        ),
      ],
    );
  }
}