import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'product_cache_service.dart';
import 'donation_cache_service.dart';
import 'lost_found_cache_service.dart';
import '../config/api_config.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  static const _storage = FlutterSecureStorage();
  static Map<String, dynamic>? _profileData;
  static Map<String, List<String>>? _userActivityIds; // Store only IDs
  static DateTime? _lastActivitySync;
  static const _activityCacheLifetime = Duration(minutes: 5);

  factory ProfileService() => _instance;
  ProfileService._internal();

  static Future<void> initialize() async {
    await _loadFromStorage();
  }

  static Map<String, dynamic>? get profileData => _profileData;
  static Map<String, List<String>>? get activityIds => _userActivityIds;

  static bool get hasValidActivityCache {
    return _userActivityIds != null && 
           _lastActivitySync != null &&
           DateTime.now().difference(_lastActivitySync!) <= _activityCacheLifetime;
  }

  static Future<void> _loadFromStorage() async {
    try {
      final data = await _storage.read(key: 'user_profile');
      if (data != null) {
        _profileData = json.decode(data);
      }

      final activityData = await _storage.read(key: 'user_activity_ids');
      if (activityData != null) {
        final decodedData = json.decode(activityData);
        _userActivityIds = {
          'products': List<String>.from(decodedData['products'] ?? []),
          'donations': List<String>.from(decodedData['donations'] ?? []),
          'lost_items': List<String>.from(decodedData['lost_items'] ?? []),
          'purchasedProducts': List<String>.from(decodedData['purchasedProducts'] ?? []),
        };
      }

      final lastSyncData = await _storage.read(key: 'last_activity_sync');
      if (lastSyncData != null) {
        _lastActivitySync = DateTime.parse(lastSyncData);
      }
    } catch (e) {
      print('Error loading profile from storage: $e');
    }
  }

  static Future<void> cacheUserResponse(Map<String, dynamic> response) async {
    if (response['user'] != null) {
      _profileData = response['user'];
      await _storage.write(
        key: 'user_profile',
        value: json.encode(_profileData)
      );
    }

    if (response['activity'] != null) {
      // Store product IDs
      _userActivityIds = {
        'products': _extractIds(response['activity']['products']),
        'donations': _extractIds(response['activity']['donations']),
        'lost_items': _extractIds(response['activity']['lost_items']),
        'purchasedProducts': _extractIds(response['activity']['purchasedProducts']),
      };
      
      // Cache full objects in respective services
      if (response['activity']['products'] != null) {
        for (var product in response['activity']['products']) {
          await ProductCacheService.cacheProduct(product['_id'], product);
        }
      }
      
      if (response['activity']['donations'] != null) {
        for (var donation in response['activity']['donations']) {
          await DonationCacheService.cacheDonation(donation['_id'], donation);
        }
      }
      
      if (response['activity']['lost_items'] != null) {
        for (var item in response['activity']['lost_items']) {
          await LostFoundCacheService.cacheItem(item['_id'], item);
        }
      }

      // Store activity IDs in secure storage
      await _storage.write(
        key: 'user_activity_ids',
        value: json.encode({
          'products': _userActivityIds!['products'],
          'donations': _userActivityIds!['donations'],
          'lost_items': _userActivityIds!['lost_items'],
          'purchasedProducts': _userActivityIds!['purchasedProducts'],
        })
      );
      
      _lastActivitySync = DateTime.now();
      await _storage.write(
        key: 'last_activity_sync',
        value: _lastActivitySync!.toIso8601String()
      );
    }
  }

  static List<String> _extractIds(List<dynamic>? items) {
    if (items == null) return [];
    return items.where((item) => item['_id'] != null)
               .map((item) => item['_id'].toString())
               .toList();
  }

  static Future<bool> fetchAndUpdateProfile() async {
    try {
      final authCookie = await _storage.read(key: 'authCookie');
      if (authCookie == null) return false;

      final response = await http.get(
        Uri.parse(ApiConfig.userProfileUrl),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          await cacheUserResponse(data);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error fetching profile: $e');
      return false;
    }
  }

  static Future<bool> fetchAndCacheUserProfile() async {
    try {
      final authCookie = await _storage.read(key: 'authCookie');
      if (authCookie == null) return false;

      final response = await http.get(
        Uri.parse(ApiConfig.userProfileUrl),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache user profile data
          _profileData = data['user'];
          await _storage.write(
            key: 'user_profile',
            value: json.encode(_profileData)
          );

          // Extract and store activity IDs
          _userActivityIds = {
            'products': _extractIds(data['activity']['products']),
            'donations': _extractIds(data['activity']['donations']), 
            'lost_items': _extractIds(data['activity']['lost_items']),
            'purchasedProducts': _extractIds(data['activity']['purchasedProducts'])
          };

          // Cache IDs
          await _storage.write(
            key: 'user_activity_ids',
            value: json.encode(_userActivityIds)
          );

          // Update timestamp
          _lastActivitySync = DateTime.now();
          await _storage.write(
            key: 'last_activity_sync',
            value: _lastActivitySync!.toIso8601String()
          );

          // Delegate caching of actual items to respective services
          if (data['activity']['products'] != null) {
            for (var product in data['activity']['products']) {
              await ProductCacheService.cacheProduct(product['_id'], product);
            }
          }

          if (data['activity']['donations'] != null) {
            for (var donation in data['activity']['donations']) {
              await DonationCacheService.cacheDonation(donation['_id'], donation);
            }
          }

          if (data['activity']['lost_items'] != null) {
            for (var item in data['activity']['lost_items']) {
              await LostFoundCacheService.cacheItem(item['_id'], item);
            }
          }

          return true;
        }
      }
      return false;
    } catch (e) {
      print('Error fetching profile: $e');
      return false;
    }
  }

  static Future<void> clearProfile() async {
    _profileData = null;
    _userActivityIds = null;
    _lastActivitySync = null;
    await _storage.delete(key: 'user_profile');
    await _storage.delete(key: 'user_activity_ids');
    await _storage.delete(key: 'last_activity_sync');
  }
}
