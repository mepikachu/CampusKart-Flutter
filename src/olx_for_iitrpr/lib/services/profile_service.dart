import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'product_cache_service.dart';
import 'donation_cache_service.dart';
import 'lost_found_cache_service.dart';
import 'server.dart';

/// Service for managing user profile data caching and synchronization
class ProfileService {
  // Singleton implementation
  static final ProfileService _instance = ProfileService._internal();
  static const _storage = FlutterSecureStorage();
  
  // In-memory caches with user ID as key
  static final Map<String, Map<String, dynamic>> _userProfiles = {};
  static final Map<String, Map<String, List<String>>> _userActivities = {};
  static final Map<String, DateTime> _lastActivitySyncs = {};
  
  // Cache configuration
  static const _activityCacheLifetime = Duration(minutes: 5);
  
  // Storage keys
  static const String _profilePrefix = 'user_profile_';
  static const String _activityPrefix = 'user_activity_';
  static const String _syncPrefix = 'last_sync_';
  
  factory ProfileService() => _instance;

  ProfileService._internal();

  /// Initialize the service and load cached data
  static Future<void> initialize() async {
    await _loadFromStorage();
    // Attempt to refresh data in the background
    fetchAndUpdateProfile();
  }

  /// Access the cached profile data for a specific user
  static Map<String, dynamic>? getProfileData(String userId) => _userProfiles[userId];

  /// Access the cached activity IDs for a specific user
  static Map<String, List<String>>? getActivityIds(String userId) => _userActivities[userId];

  /// Check if the activity cache is still valid for a specific user
  static bool hasValidActivityCache(String userId) {
    return _userActivities.containsKey(userId) &&
        _lastActivitySyncs.containsKey(userId) &&
        DateTime.now().difference(_lastActivitySyncs[userId]!) <= _activityCacheLifetime;
  }

  /// Load cached data from secure storage
  static Future<void> _loadFromStorage() async {
    try {
      final allData = await _storage.readAll();
      
      for (final entry in allData.entries) {
        final key = entry.key;
        final value = entry.value;
        
        if (key.startsWith(_profilePrefix)) {
          final userId = key.substring(_profilePrefix.length);
          _userProfiles[userId] = json.decode(value);
        } else if (key.startsWith(_activityPrefix)) {
          final userId = key.substring(_activityPrefix.length);
          final decodedData = json.decode(value);
          _userActivities[userId] = {
            'products': List<String>.from(decodedData['products'] ?? []),
            'donations': List<String>.from(decodedData['donations'] ?? []),
            'lost_items': List<String>.from(decodedData['lost_items'] ?? []),
            'purchasedProducts': List<String>.from(decodedData['purchasedProducts'] ?? []),
          };
        } else if (key.startsWith(_syncPrefix)) {
          final userId = key.substring(_syncPrefix.length);
          _lastActivitySyncs[userId] = DateTime.parse(value);
        }
      }
    } catch (e) {
      print('Error loading profiles from storage: $e');
    }
  }

  /// Cache a user response containing profile and activity data
  static Future<void> cacheUserProfile(Map<String, dynamic> response) async {
    if (response['user'] == null || response['user']['_id'] == null) {
      print('Invalid user data in response');
      return;
    }

    final userId = response['user']['_id'].toString();
    
    if (response['user'] != null) {
      _userProfiles[userId] = response['user'];
      await _storage.write(
        key: '$_profilePrefix$userId',
        value: json.encode(_userProfiles[userId])
      );
    }

    if (response['activity'] != null) {
      final activity = response['activity'];
      
      // Extract and store activity IDs for this user
      _userActivities[userId] = {
        'products': _extractIds(activity['products'] as List?),
        'donations': _extractIds(activity['donations'] as List?),
        'lost_items': _extractIds(activity['lost_items'] as List?),
        'purchasedProducts': _extractIds(activity['purchasedProducts'] as List?),
      };
      
      // Cache full objects in respective services
      if (activity['products'] != null) {
        for (var product in activity['products'] as List) {
          if (product is Map<String, dynamic> && product['_id'] != null) {
            await ProductCacheService.cacheProduct(
              product['_id'].toString(),
              product
            );
          }
        }
      }

      if (activity['purchasedProducts'] != null) {
        for (var purchasedProduct in activity['purchasedProducts'] as List) {
          if (purchasedProduct is Map<String, dynamic> && purchasedProduct['_id'] != null) {
            await ProductCacheService.cacheProduct(
              purchasedProduct['_id'].toString(),
              purchasedProduct
            );
          }
        }
      }
      
      if (activity['donations'] != null) {
        for (var donation in activity['donations'] as List) {
          if (donation is Map<String, dynamic> && donation['_id'] != null) {
            await DonationCacheService.cacheDonation(
              donation['_id'].toString(),
              donation
            );
          }
        }
      }
      
      if (activity['lost_items'] != null) {
        for (var item in activity['lost_items'] as List) {
          if (item is Map<String, dynamic> && item['_id'] != null) {
            await LostFoundCacheService.cacheItem(
              item['_id'].toString(),
              item
            );
          }
        }
      }

      // Store activity IDs in secure storage with proper typing
      await _storage.write(
        key: '$_activityPrefix$userId',
        value: json.encode(_userActivities[userId])
      );
      
      _lastActivitySyncs[userId] = DateTime.now();
      await _storage.write(
        key: '$_syncPrefix$userId',
        value: _lastActivitySyncs[userId]!.toIso8601String()
      );
    }
  }

  /// Extract IDs from a list of items, ensuring string conversion
  static List<String> _extractIds(List? items) {
    if (items == null) return [];
    return items
        .where((item) => item is Map<String, dynamic> && item['_id'] != null)
        .map((item) => item['_id'].toString())
        .toList();
  }

  /// Fetch and update profile data from the server
  static Future<bool> fetchAndUpdateProfile() async {
    try {
      final authCookie = await _storage.read(key: 'authCookie');
      if (authCookie == null) return false;
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          await cacheUserProfile(data);
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('Error fetching profile: $e');
      return false;
    }
  }

  /// Clear profile data for a specific user
  static Future<void> clearUserProfile(String userId) async {
    _userProfiles.remove(userId);
    _userActivities.remove(userId);
    _lastActivitySyncs.remove(userId);
    
    try {
      await _storage.delete(key: '$_profilePrefix$userId');
      await _storage.delete(key: '$_activityPrefix$userId');
      await _storage.delete(key: '$_syncPrefix$userId');
    } catch (e) {
      print('Error clearing profile cache for user $userId: $e');
    }
  }

  /// Clear all profile data
  static Future<void> clearAllProfiles() async {
    _userProfiles.clear();
    _userActivities.clear();
    _lastActivitySyncs.clear();
    
    try {
      final allKeys = await _storage.readAll();
      for (var key in allKeys.keys) {
        if (key.startsWith(_profilePrefix) ||
            key.startsWith(_activityPrefix) ||
            key.startsWith(_syncPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (e) {
      print('Error clearing all profile caches: $e');
    }
  }
}
