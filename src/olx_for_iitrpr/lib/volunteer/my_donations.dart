import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'server.dart';

class MyDonationCollections extends StatefulWidget {
  const MyDonationCollections({super.key});

  @override
  State<MyDonationCollections> createState() => _MyDonationCollectionsState();
}

class _MyDonationCollectionsState extends State<MyDonationCollections> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> donations = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadDonations();
  }

  Future<void> _loadDonations() async {
    setState(() => isLoading = true);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('$serverUrl/api/donations/volunteer/donations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      final responseBody = json.decode(response.body);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        setState(() {
          donations = (responseBody['donations'] as List<dynamic>).map((donation) => {
            'id': donation['_id'] ?? '',
            'name': donation['name'] ?? 'No Name',
            'description': donation['description'] ?? 'No description',
            'status': donation['status'] ?? 'available',
            'donationDate': donation['donationDate'] ?? donation['createdAt'],
            'collectedBy': donation['collectedBy'],
            'donatedBy': donation['donatedBy'],
          }).toList();
        });
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch donations');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Donation Collections'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        onRefresh: _loadDonations,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage.isNotEmpty
                ? Center(child: Text(errorMessage))
                : donations.isEmpty
                    ? const Center(
                        child: Text(
                          'No donations found',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: donations.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final donation = donations[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(
                                donation['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(donation['description']),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Status: ${donation['status'].toString().toUpperCase()}',
                                    style: TextStyle(
                                      color: _getStatusColor(donation['status']),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Date: ${_formatDate(donation['donationDate'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                _getStatusIcon(donation['status']),
                                color: _getStatusColor(donation['status']),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'N/A';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'collected':
        return Icons.check_circle;
      case 'available':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'collected':
        return Colors.green;
      case 'available':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
