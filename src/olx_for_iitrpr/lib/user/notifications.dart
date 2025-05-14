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
    // Save read timestamp when opening notifications
    _saveLastReadTime();
  }

  Future<void> _saveLastReadTime() async {
    try {
      await _secureStorage.write(
        key: 'last_read_notification_time',
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('Error saving notification read time: $e');
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => isLoading = true);
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // First check if user is authenticated
      if (authCookie == null) {
        throw Exception('Not authenticated');
      }

      // Fetch notifications with proper error handling
      final response = await http.get(
        Uri.parse('$serverUrl/api/user/notifications'),  // Updated endpoint
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            notifications = data['notifications'].map((notification) {
              // Add read status if not present
              if (!notification.containsKey('read')) {
                notification['read'] = false;
              }
              return notification;
            }).toList();
            isLoading = false;
          });
          
          // Save last read time
          await _saveLastReadTime();
        } else {
          throw Exception(data['message'] ?? 'Failed to load notifications');
        }
      } else if (response.statusCode == 401) {
        // Handle unauthorized access
        await _secureStorage.delete(key: 'authCookie');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          notifications = [];  // Clear notifications on error
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.put(
        Uri.parse('$serverUrl/api/notifications/$notificationId/read'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = notifications.indexWhere((n) => n['_id'] == notificationId);
          if (index != -1) {
            notifications[index]['read'] = true;
          }
        });
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Icon _getNotificationIcon(String type) {
    switch (type) {
      case 'offer':
      case 'offer_received':
        return const Icon(Icons.local_offer, color: Colors.orange);
      case 'offer_accepted':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'offer_rejected':
        return const Icon(Icons.cancel, color: Colors.red);
      case 'product_update':
        return const Icon(Icons.update, color: Colors.blue);
      case 'product_deleted':
        return const Icon(Icons.delete, color: Colors.red);
      case 'warning':
        return const Icon(Icons.warning, color: Colors.amber);
      case 'account_blocked':
        return const Icon(Icons.block, color: Colors.red);
      case 'account_unblocked':
        return const Icon(Icons.lock_open, color: Colors.green);
      default:
        return const Icon(Icons.notifications, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
        actions: [
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: () async {
                try {
                  final authCookie = await _secureStorage.read(key: 'authCookie');
                  final response = await http.put(
                    Uri.parse('$serverUrl/api/user/notifications/read-all'),
                    headers: {
                      'Content-Type': 'application/json',
                      'auth-cookie': authCookie ?? '',
                    },
                  );

                  if (response.statusCode == 200) {
                    setState(() {
                      notifications = notifications.map((notification) {
                        notification['read'] = true;
                        return notification;
                      }).toList();
                    });
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to mark notifications as read'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
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
                  onRefresh: _loadNotifications,
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
                            if (!notification['read']) {
                              await markAsRead(notification['_id']);
                            }
                            
                            if (notification['productId'] != null && mounted) {
                              try {
                                final authCookie = await _secureStorage.read(key: 'authCookie');
                                final response = await http.get(
                                  Uri.parse('$serverUrl/api/products/${notification['productId']}'),
                                  headers: {
                                    'Content-Type': 'application/json',
                                    'auth-cookie': authCookie ?? '',
                                  },
                                );

                                if (response.statusCode == 200) {
                                  final data = json.decode(response.body);
                                  if (data['success'] && mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProductDetailsScreen(
                                          product: data['product'],
                                        ),
                                      ),
                                    );
                                  } else {
                                    throw Exception('Product not found');
                                  }
                                } else {
                                  throw Exception('Failed to load product');
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: ${e.toString()}'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
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