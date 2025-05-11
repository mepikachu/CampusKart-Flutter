import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for caching donation data and images to improve loading times
class DonationCacheService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Duration _cacheLifetime = Duration(minutes: 10);

  // In-memory cache
  static final Map<String, Uint8List> _mainImageCache = {};
  static final Map<String, List<Uint8List>> _allImagesCache = {};
  static final Map<String, Map<String, dynamic>> _donationCache = {};
  static final Map<String, int> _numImagesCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Cache keys
  static String _donationKey(String id) => 'donation_$id';
  static String _imageKey(String id) => 'donation_image_$id';
  static String _allImagesKey(String id) => 'donation_all_images_$id';
  static String _numImagesKey(String id) => 'donation_num_images_$id';
  static String _timestampKey(String id) => 'donation_timestamp_$id';
  static const String _donationsListKey = 'donations_list';

  /// Cache a single donation
  static Future<void> cacheDonation(String id, Map<String, dynamic> donation) async {
    try {
      // Store in memory
      _donationCache[id] = Map.from(donation);
      _cacheTimestamps[id] = DateTime.now();
      
      // Store in secure storage
      await _secureStorage.write(key: _donationKey(id), value: jsonEncode(donation));
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching donation: $e');
    }
  }

  /// Cache a list of donations
  static Future<void> cacheDonations(List<dynamic> donations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_donationsListKey, jsonEncode(donations));
      
      for (var donation in donations) {
        if (donation != null && donation['_id'] != null) {
          await cacheDonation(donation['_id'], donation);
        }
      }
    } catch (e) {
      print('Error caching donations: $e');
    }
  }

  /// Cache a single image (main image)
  static Future<void> cacheImage(String id, Uint8List imageBytes, int numImages) async {
    try {
      // Store in memory
      _mainImageCache[id] = imageBytes;
      _numImagesCache[id] = numImages;
      _cacheTimestamps[id] = DateTime.now();
      
      // Store in secure storage
      final String base64Image = base64Encode(imageBytes);
      await _secureStorage.write(key: _imageKey(id), value: base64Image);
      await _secureStorage.write(key: _numImagesKey(id), value: numImages.toString());
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching donation image: $e');
    }
  }

  /// Cache all images for a donation
  static Future<void> cacheAllImages(String id, List<Uint8List> images) async {
    try {
      // Store in memory
      _allImagesCache[id] = List.from(images);
      _numImagesCache[id] = images.length;
      _cacheTimestamps[id] = DateTime.now();
      
      // Convert to base64 for storage
      final List<String> base64Images = images.map((e) => base64Encode(e)).toList();
      
      // Use SharedPreferences for larger data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_allImagesKey(id), base64Images);
      
      // Store timestamp and number of images in secure storage
      await _secureStorage.write(key: _numImagesKey(id), value: images.length.toString());
      await _secureStorage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
    } catch (e) {
      print('Error caching all donation images: $e');
    }
  }

  /// Get cached donations list
  static Future<List<dynamic>?> getCachedDonations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_donationsListKey);
      if (jsonData == null) return null;
      return jsonDecode(jsonData);
    } catch (e) {
      print('Error getting cached donations: $e');
      return null;
    }
  }

  /// Get a cached donation
  static Future<Map<String, dynamic>?> getCachedDonation(String id) async {
    try {
      // Check memory cache first
      if (_donationCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _donationCache[id];
        }
      }
      
      // Check secure storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearDonationCache(id);
        return null;
      }
      
      final jsonData = await _secureStorage.read(key: _donationKey(id));
      if (jsonData == null) return null;
      
      final donation = jsonDecode(jsonData);
      
      // Update memory cache
      _donationCache[id] = Map<String, dynamic>.from(donation);
      _cacheTimestamps[id] = DateTime.now();
      
      return donation;
    } catch (e) {
      print('Error getting cached donation: $e');
      return null;
    }
  }

  /// Get cached image
  static Future<Uint8List?> getCachedImage(String id) async {
    try {
      // Check memory cache first
      if (_mainImageCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _mainImageCache[id];
        }
      }
      
      // Check secure storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearImageCache(id);
        return null;
      }
      
      final base64Image = await _secureStorage.read(key: _imageKey(id));
      if (base64Image == null) return null;
      
      final imageBytes = base64Decode(base64Image);
      
      // Update memory cache
      _mainImageCache[id] = imageBytes;
      _cacheTimestamps[id] = DateTime.now();
      
      return imageBytes;
    } catch (e) {
      print('Error getting cached donation image: $e');
      return null;
    }
  }

  /// Get all cached images
  static Future<List<Uint8List>?> getCachedAllImages(String id) async {
    try {
      // Check memory cache first
      if (_allImagesCache.containsKey(id)) {
        final timestamp = _cacheTimestamps[id];
        if (timestamp != null && DateTime.now().difference(timestamp) <= _cacheLifetime) {
          return _allImagesCache[id];
        }
      }
      
      // Check storage
      final timestampStr = await _secureStorage.read(key: _timestampKey(id));
      if (timestampStr == null) return null;
      
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp) > _cacheLifetime) {
        // Cache expired
        await _clearImageCache(id);
        return null;
      }
      
      // Get from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final List<String>? base64Images = prefs.getStringList(_allImagesKey(id));
      if (base64Images == null || base64Images.isEmpty) return null;
      
      final List<Uint8List> images = base64Images.map((e) => base64Decode(e)).toList();
      
      // Update memory cache
      _allImagesCache[id] = List.from(images);
      _cacheTimestamps[id] = DateTime.now();
      
      return images;
    } catch (e) {
      print('Error getting all cached donation images: $e');
      return null;
    }
  }

  /// Get cached number of images
  static Future<int?> getCachedNumImages(String id) async {
    try {
      // Check memory cache first
      if (_numImagesCache.containsKey(id)) {
        return _numImagesCache[id];
      }
      
      // Check secure storage
      final numImagesStr = await _secureStorage.read(key: _numImagesKey(id));
      if (numImagesStr == null) return null;
      
      final numImages = int.tryParse(numImagesStr);
      if (numImages != null) {
        _numImagesCache[id] = numImages;
      }
      
      return numImages;
    } catch (e) {
      print('Error getting cached num images: $e');
      return null;
    }
  }

  /// Check if cache is still valid
  static bool isCacheValid(String id) {
    return _cacheTimestamps.containsKey(id) && 
           DateTime.now().difference(_cacheTimestamps[id]!) <= _cacheLifetime;
  }

  /// Clear donation cache
  static Future<void> _clearDonationCache(String id) async {
    try {
      await _secureStorage.delete(key: _donationKey(id));
      await _secureStorage.delete(key: _timestampKey(id));
      _donationCache.remove(id);
      _cacheTimestamps.remove(id);
    } catch (e) {
      print('Error clearing donation cache: $e');
    }
  }

  /// Clear image cache
  static Future<void> _clearImageCache(String id) async {
    try {
      await _secureStorage.delete(key: _imageKey(id));
      await _secureStorage.delete(key: _numImagesKey(id));
      await _secureStorage.delete(key: _timestampKey(id));
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_allImagesKey(id));
      
      _mainImageCache.remove(id);
      _allImagesCache.remove(id);
      _numImagesCache.remove(id);
    } catch (e) {
      print('Error clearing donation image cache: $e');
    }
  }

  /// Clear specific donation's cache
  static Future<void> clearCache(String id) async {
    try {
      await _clearDonationCache(id);
      await _clearImageCache(id);
    } catch (e) {
      print('Error clearing donation cache: $e');
    }
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_donationsListKey);
      
      // Clear all memory caches
      _mainImageCache.clear();
      _allImagesCache.clear();
      _donationCache.clear();
      _numImagesCache.clear();
      _cacheTimestamps.clear();
    } catch (e) {
      print('Error clearing all donation caches: $e');
    }
  }
}
