import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DonationCacheService {
  static const _storage = FlutterSecureStorage();
  static const _cacheLifetime = Duration(minutes: 10);
  
  // Memory cache
  static final Map<String, Uint8List> _mainImages = {};
  static final Map<String, List<Uint8List>> _allImages = {};
  static final Map<String, Map<String, dynamic>> _donations = {};
  static final Map<String, int> _numImages = {};
  static final Map<String, DateTime> _timestamps = {};

  // Keys
  static String _donationKey(String id) => 'donation_$id';
  static String _imageKey(String id) => 'donation_image_$id';
  static String _allImagesKey(String id) => 'donation_all_images_$id';
  static String _numImagesKey(String id) => 'donation_num_images_$id';
  static String _timestampKey(String id) => 'donation_timestamp_$id';

  static Future<void> cacheDonation(String id, Map<String, dynamic> donation) async {
    _donations[id] = Map<String, dynamic>.from(donation);
    _timestamps[id] = DateTime.now();
    await _storage.write(key: _donationKey(id), value: jsonEncode(donation));
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<void> cacheImage(String id, Uint8List bytes, int numImages) async {
    _mainImages[id] = bytes;
    _numImages[id] = numImages;
    _timestamps[id] = DateTime.now();
    await _storage.write(key: _imageKey(id), value: base64Encode(bytes));
    await _storage.write(key: _numImagesKey(id), value: numImages.toString());
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<void> cacheAllImages(String id, List<Uint8List> images) async {
    _allImages[id] = List<Uint8List>.from(images);
    _numImages[id] = images.length;
    _timestamps[id] = DateTime.now();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _allImagesKey(id), 
      images.map((e) => base64Encode(e)).toList()
    );
    
    await _storage.write(key: _numImagesKey(id), value: images.length.toString());
    await _storage.write(key: _timestampKey(id), value: DateTime.now().toIso8601String());
  }

  static Future<Map<String, dynamic>?> getCachedDonation(String id) async {
    if (_donations.containsKey(id) && _isCacheValid(id)) {
      return _donations[id];
    }

    final data = await _storage.read(key: _donationKey(id));
    final timestamp = await _storage.read(key: _timestampKey(id));
    
    if (data != null && timestamp != null) {
      final lastUpdate = DateTime.parse(timestamp);
      if (DateTime.now().difference(lastUpdate) <= _cacheLifetime) {
        final donation = json.decode(data);
        _donations[id] = Map<String, dynamic>.from(donation);
        return donation;
      }
    }
    
    return null;
  }

  static Future<Uint8List?> getCachedImage(String id) async {
    if (_mainImages.containsKey(id) && _isCacheValid(id)) {
      return _mainImages[id];
    }

    final data = await _storage.read(key: _imageKey(id));
    final timestamp = await _storage.read(key: _timestampKey(id));
    
    if (data != null && timestamp != null) {
      final lastUpdate = DateTime.parse(timestamp);
      if (DateTime.now().difference(lastUpdate) <= _cacheLifetime) {
        final bytes = base64Decode(data);
        _mainImages[id] = bytes;
        return bytes;
      }
    }
    
    return null;
  }

  static Future<List<Uint8List>?> getCachedAllImages(String id) async {
    if (_allImages.containsKey(id) && _isCacheValid(id)) {
      return _allImages[id];
    }

    final prefs = await SharedPreferences.getInstance();
    final timestamp = await _storage.read(key: _timestampKey(id));
    final data = prefs.getStringList(_allImagesKey(id));
    
    if (data != null && timestamp != null) {
      final lastUpdate = DateTime.parse(timestamp);
      if (DateTime.now().difference(lastUpdate) <= _cacheLifetime) {
        final images = data.map((e) => base64Decode(e)).toList();
        _allImages[id] = images;
        return images;
      }
    }
    
    return null;
  }

  static bool _isCacheValid(String id) {
    return _timestamps.containsKey(id) && 
      DateTime.now().difference(_timestamps[id]!) <= _cacheLifetime;
  }

  static Future<void> clearCache(String id) async {
    _donations.remove(id);
    _mainImages.remove(id);
    _allImages.remove(id);
    _numImages.remove(id);
    _timestamps.remove(id);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_allImagesKey(id));
    
    await _storage.delete(key: _donationKey(id));
    await _storage.delete(key: _imageKey(id));
    await _storage.delete(key: _numImagesKey(id));
    await _storage.delete(key: _timestampKey(id));
  }
}
