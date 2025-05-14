import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../user/server.dart';

class NotificationService {
  static const storage = FlutterSecureStorage();
  static Timer? _pollingTimer;
  static final StreamController<List<dynamic>> _notificationController = 
      StreamController<List<dynamic>>.broadcast();

  static Stream<List<dynamic>> get notificationStream => 
      _notificationController.stream;

  static void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) => fetchNotifications(),
    );
  }

  static void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  static Future<void> fetchNotifications() async {
    try {
      final authCookie = await storage.read(key: 'authCookie');
      if (authCookie == null) return;

      final response = await http.get(
        Uri.parse('$serverUrl/api/user/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          _notificationController.add(data['notifications']);
          // Cache notifications
          await storage.write(
            key: 'notifications',
            value: json.encode(data['notifications']),
          );
        }
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
  }

  static Future<void> markAsRead(String notificationId) async {
    try {
      final authCookie = await storage.read(key: 'authCookie');
      if (authCookie == null) return;

      await http.put(
        Uri.parse('$serverUrl/api/notifications/$notificationId/read'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  static Future<void> markAllAsRead() async {
    try {
      final authCookie = await storage.read(key: 'authCookie');
      if (authCookie == null) return;

      await http.put(
        Uri.parse('$serverUrl/api/notifications/read-all'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }
}
