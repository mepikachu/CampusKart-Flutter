import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  static const _storage = FlutterSecureStorage();
  static Map<String, dynamic>? _profileData;

  factory ProfileService() => _instance;
  ProfileService._internal();

  static Future<void> initialize() async {
    await _loadFromStorage();
  }

  static Map<String, dynamic>? get profileData => _profileData;

  static Future<void> _loadFromStorage() async {
    try {
      final data = await _storage.read(key: 'user_profile');
      if (data != null) {
        _profileData = json.decode(data);
      }
    } catch (e) {
      print('Error loading profile from storage: $e');
    }
  }

  static Future<void> cacheProfile(Map<String, dynamic> data) async {
    _profileData = data;
    await _storage.write(
      key: 'user_profile',
      value: json.encode(data)
    );
  }

  static Future<bool> fetchAndUpdateProfile() async {
    try {
      final authCookie = await _storage.read(key: 'authCookie');
      if (authCookie == null) return false;

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          _profileData = data['user'];
          await _storage.write(
            key: 'user_profile',
            value: json.encode(_profileData),
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error fetching profile: $e');
      return false;
    }
  }

  static Future<bool> updateProfile(Map<String, dynamic> updates) async {
    try {
      final authCookie = await _storage.read(key: 'authCookie');
      if (authCookie == null) return false;

      final response = await http.put(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
        body: json.encode(updates),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          _profileData = data['user'];
          await _storage.write(
            key: 'user_profile', 
            value: json.encode(_profileData)
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }

  static Future<void> clearProfile() async {
    _profileData = null;
    await _storage.delete(key: 'user_profile');
  }
}
