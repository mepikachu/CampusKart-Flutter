import 'server.dart';

class ApiConfig {
  // Base URL for the backend API
  static const String baseUrl = '$serverUrl ';

  // API endpoints
  static String get loginUrl => '$baseUrl/api/login';
  static String get logoutUrl => '$baseUrl/api/logout';
  static String get signupUrl => '$baseUrl/api/signup';
  static String get sendOtpUrl => '$baseUrl/api/send-register-otp';
  static String get verifyOtpUrl => '$baseUrl/api/verify-otp';
  static String get userProfileUrl => '$baseUrl/api/users/me';
  static String get productsUrl => '$baseUrl/api/products';
  static String get lostItemsUrl => '$baseUrl/api/lost-items';
  static String get donationsUrl => '$baseUrl/api/donations';
  static String get conversationsUrl => '$baseUrl/api/conversations';
  static String get notificationsUrl => '$baseUrl/api/notifications';
  static String get adminUsersUrl => '$baseUrl/api/admin/users';
  static String get volunteerRequestsUrl => '$baseUrl/api/volunteer-requests';
  
  // Helper methods to construct URLs with parameters
  static String getProductUrl(String productId) => '$productsUrl/$productId';
  static String getProductImageUrl(String productId) => '$productsUrl/$productId/main_image';
  static String getProductImagesUrl(String productId) => '$productsUrl/$productId/images';
  static String getProductOffersUrl(String productId) => '$productsUrl/$productId/offers';
  
  static String getLostItemUrl(String itemId) => '$lostItemsUrl/$itemId';
  static String getLostItemImageUrl(String itemId) => '$lostItemsUrl/$itemId/main_image';
  static String getLostItemImagesUrl(String itemId) => '$lostItemsUrl/$itemId/images';
  
  static String getDonationUrl(String donationId) => '$donationsUrl/$donationId';
  static String getDonationImageUrl(String donationId) => '$donationsUrl/$donationId/main_image';
  
  static String getConversationUrl(String conversationId) => '$conversationsUrl/$conversationId';
  static String getConversationMessagesUrl(String conversationId) => '$conversationsUrl/$conversationId/messages';
  
  static String getUserUrl(String userId) => '$baseUrl/api/users/$userId';
  static String getUserProfilePictureUrl(String userId) => '$baseUrl/api/users/$userId/profile-picture';
}
