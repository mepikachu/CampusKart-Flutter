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
        Uri.parse('$serverUrl/api/donations/volunteer/donations'), // Updated endpoint
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      final responseBody = json.decode(response.body);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        setState(() {
          donations = responseBody['donations'] ?? [];
          errorMessage = '';
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
                ? Center(child: Text('Error: $errorMessage'))
                : donations.isEmpty
                    ? const Center(child: Text('No donations found'))
                    : ListView.builder(
                        itemCount: donations.length,
                        itemBuilder: (context, index) {
                          final donation = donations[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              title: Text(donation['title'] ?? 'Unnamed Donation'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Status: ${donation['status']}'),
                                  Text('Date: ${_formatDate(donation['date'])}'),
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
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
