import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_description.dart';
import 'server.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> notifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => isLoading = true);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final response = await http.get(
        Uri.parse('$serverUrl/api/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            notifications = data['notifications'];
            isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load notifications');
      }
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'offer':
      case 'offer_received':
        return Icons.local_offer;
      case 'offer_accepted':
        return Icons.check_circle;
      case 'offer_rejected':
        return Icons.cancel;
      case 'product_update':
        return Icons.update;
      case 'product_deleted':
        return Icons.delete;
      case 'warning':
        return Icons.warning;
      case 'account_blocked':
        return Icons.block;
      case 'account_unblocked':
        return Icons.lock_open;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'offer':
      case 'offer_received':
        return Colors.orange;
      case 'offer_accepted':
        return Colors.green;
      case 'offer_rejected':
        return Colors.red;
      case 'product_update':
        return Colors.blue;
      case 'product_deleted':
        return Colors.red;
      case 'warning':
        return Colors.amber;
      case 'account_blocked':
        return Colors.red;
      case 'account_unblocked':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : notifications.isEmpty
          ? const Center(
              child: Text('No notifications'),
            )
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: ListTile(
                      leading: Icon(
                        _getNotificationIcon(notification['type']),
                        color: _getNotificationColor(notification['type']),
                      ),
                      title: Text(notification['message']),
                      subtitle: Text(
                        DateTime.parse(notification['createdAt'])
                          .toLocal()
                          .toString()
                          .split('.')[0]
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}