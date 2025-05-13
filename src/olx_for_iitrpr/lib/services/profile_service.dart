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
  
  // In-memory caches
  static Map<String, dynamic>? _profileData;
  static Map<String, List<String>>? _userActivityIds; // Store only IDs
  static DateTime? _lastActivitySync;
  
  // Cache configuration
  static const _activityCacheLifetime = Duration(minutes: 5);
  
  // Storage keys
  static const String _profileKey = 'user_profile';
  static const String _activityIdsKey = 'user_activity_ids';
  static const String _activitySyncKey = 'last_activity_sync';

  // Constants for storage
  static const _currentUserKey = 'current_user_profile';
  static const _otherUsersPrefix = 'user_profile_';
  static const _profilesCacheLifetime = Duration(hours: 1);
  
  // In-memory cache for other users
  static final Map<String, Map<String, dynamic>> _otherUsersCache = {};
  static final Map<String, DateTime> _otherUsersCacheTimestamp = {};

  factory ProfileService() => _instance;

  ProfileService._internal();

  /// Initialize the service and load cached data
  static Future<void> initialize() async {
    await _loadFromStorage();
    // Attempt to refresh data in the background
    fetchAndUpdateProfile();
  }

  /// Access the cached profile data
  static Map<String, dynamic>? get profileData => _profileData;

  /// Access the cached activity IDs
  static Map<String, List<String>>? get activityIds => _userActivityIds;

  /// Check if the activity cache is still valid
  static bool get hasValidActivityCache {
    return _userActivityIds != null &&
        _lastActivitySync != null &&
        DateTime.now().difference(_lastActivitySync!) <= _activityCacheLifetime;
  }

  /// Load cached data from secure storage
  static Future<void> _loadFromStorage() async {
    try {
      final data = await _storage.read(key: _profileKey);
      if (data != null) {
        _profileData = json.decode(data);
      }

      final activityData = await _storage.read(key: _activityIdsKey);
      if (activityData != null) {
        final decodedData = json.decode(activityData);
        _userActivityIds = {
          'products': List<String>.from(decodedData['products'] ?? []),
          'donations': List<String>.from(decodedData['donations'] ?? []),
          'lost_items': List<String>.from(decodedData['lost_items'] ?? []),
          'purchasedProducts': List<String>.from(decodedData['purchasedProducts'] ?? []),
        };
      }

      final lastSyncData = await _storage.read(key: _activitySyncKey);
      if (lastSyncData != null) {
        _lastActivitySync = DateTime.parse(lastSyncData);
      }
    } catch (e) {
      print('Error loading profile from storage: $e');
    }
  }

  /// Cache a user response containing profile and activity data
  static Future<void> cacheUserResponse(Map<String, dynamic> response) async {
    if (response['user'] != null) {
      _profileData = response['user'];
      await _storage.write(
        key: _profileKey,
        value: json.encode(_profileData)
      );
    }

    if (response['activity'] != null) {
      final activity = response['activity'];
      
      // Extract and store activity IDs, ensuring String type
      _userActivityIds = {
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
            print(item);
            await LostFoundCacheService.cacheItem(
              item['_id'].toString(),
              item
            );
          }
        }
      }

      // Store activity IDs in secure storage with proper typing
      await _storage.write(
        key: _activityIdsKey,
        value: json.encode({
          'products': _userActivityIds!['products'] ?? [],
          'donations': _userActivityIds!['donations'] ?? [],
          'lost_items': _userActivityIds!['lost_items'] ?? [],
          'purchasedProducts': _userActivityIds!['purchasedProducts'] ?? [],
        })
      );
      
      _lastActivitySync = DateTime.now();
      await _storage.write(
        key: _activitySyncKey,
        value: _lastActivitySync!.toIso8601String()
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

  /// Clear all profile data from memory and storage
  static Future<void> clearProfile() async {
    _profileData = null;
    _userActivityIds = null;
    _lastActivitySync = null;
    await _storage.delete(key: _profileKey);
    await _storage.delete(key: _activityIdsKey);
    await _storage.delete(key: _activitySyncKey);
  }

  /// Get cached profile for any user
  static Future<Map<String, dynamic>?> getCachedUserProfile(String userId) async {
    // If it's current user, use existing cache
    if (userId == _profileData?['_id']) {
      return _profileData;
    }

    // Check in-memory cache first
    if (_otherUsersCache.containsKey(userId)) {
      final timestamp = _otherUsersCacheTimestamp[userId];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) <= _profilesCacheLifetime) {
        return _otherUsersCache[userId];
      }
    }

    // Check secure storage
    try {
      final data = await _storage.read(key: '$_otherUsersPrefix$userId');
      if (data != null) {
        final profile = json.decode(data);
        _otherUsersCache[userId] = profile;
        _otherUsersCacheTimestamp[userId] = DateTime.now();
        return profile;
      }
    } catch (e) {
      print('Error loading cached profile for user $userId: $e');
    }
    return null;
  }

  /// Cache a user's profile data
  static Future<void> cacheUserProfile(String userId, Map<String, dynamic> data) async {
    // For current user, use existing caching
    if (_profileData != null && userId == _profileData!['_id']) {
      return cacheUserResponse(data);
    }

    try {
      // Cache user data
      if (data['user'] != null) {
        _otherUsersCache[userId] = data['user'];
        _otherUsersCacheTimestamp[userId] = DateTime.now();
        await _storage.write(
          key: '$_otherUsersPrefix$userId',
          value: json.encode(data['user'])
        );
      }

      // Cache activities in respective services
      if (data['activity'] != null) {
        final activity = data['activity'];
        
        // Cache products
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
        
        // Cache donations
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

        // Cache lost items
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
      }
    } catch (e) {
      print('Error caching profile for user $userId: $e');
    }
  }

  /// Clear cache for a specific user
  static Future<void> clearUserCache(String userId) async {
    _otherUsersCache.remove(userId);
    _otherUsersCacheTimestamp.remove(userId);
    await _storage.delete(key: '$_otherUsersPrefix$userId');
  }
}
