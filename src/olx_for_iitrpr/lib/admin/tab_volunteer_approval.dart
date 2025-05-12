import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'server.dart';
import 'view_profile.dart'; // Add this import

class VolunteerRequestsScreen extends StatefulWidget {
  const VolunteerRequestsScreen({super.key});

  @override
  State<VolunteerRequestsScreen> createState() => _VolunteerRequestsScreenState();
}

class _VolunteerRequestsScreenState extends State<VolunteerRequestsScreen> {
  final _secureStorage = const FlutterSecureStorage();
  List<dynamic> requests = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    fetchVolunteerRequests();
  }

  Future<void> fetchVolunteerRequests() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/volunteer-requests'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          requests = data['requests'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = data['error'] ?? 'Failed to fetch requests';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _updateRequest(String userId, String action) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/volunteer-requests/$userId/$action'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'])),
        );
        fetchVolunteerRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Operation failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _buildRequestCard(dynamic request) {
    return Card(
      elevation: 1,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ViewProfileScreen(userId: request['_id']),
            ),
          );
        },
        child: ListTile(
          title: Text(request['userName'] ?? 'No Username'),
          subtitle: Text(request['email'] ?? ''),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () => _updateRequest(request['_id'], 'approve'),
              ),
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.red),
                onPressed: () => _updateRequest(request['_id'], 'reject'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text(errorMessage))
              : requests.isEmpty
                  ? const Center(child: Text("No pending requests"))
                  : RefreshIndicator(
                      onRefresh: fetchVolunteerRequests,
                      color: Colors.black,
                      child: ListView.builder(
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          return _buildRequestCard(requests[index]);
                        },
                      ),
                    ),
    );
  }
}