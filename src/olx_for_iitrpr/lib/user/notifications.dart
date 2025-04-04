import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'product_description.dart';

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
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          notifications = data['notifications'];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Icon _getNotificationIcon(String type) {
    switch (type) {
      case 'offer':
        return const Icon(Icons.local_offer, color: Colors.blue);
      case 'offer_response':
        return const Icon(Icons.reply, color: Colors.green);
      case 'product_update':
        return const Icon(Icons.update, color: Colors.orange);
      default:
        return const Icon(Icons.notifications, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                // Mark all as read functionality can be added here
              },
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No notifications yet'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchNotifications,
                  child: ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: _getNotificationIcon(notification['type']),
                          title: Text(notification['message']),
                          subtitle: Text(
                            DateTime.parse(notification['createdAt'])
                                .toLocal()
                                .toString()
                                .split('.')[0],
                            style: TextStyle(
                                color: notification['read']
                                    ? Colors.grey
                                    : Colors.black87),
                          ),
                          tileColor:
                              notification['read'] ? null : Colors.blue.shade50,
                          onTap: () async {
                            // Mark as read and navigate to product
                            if (!notification['read']) {
                              final authCookie = await _secureStorage.read(
                                  key: 'authCookie');
                              await http.put(
                                Uri.parse(
                                    'https://olx-for-iitrpr-backend.onrender.com/api/notifications/${notification['_id']}/read'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'auth-cookie': authCookie ?? '',
                                },
                              );
                            }
                            if (mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailsScreen(
                                    product: notification['productId'],
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
