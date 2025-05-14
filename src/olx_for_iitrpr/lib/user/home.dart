import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_list.dart';
import 'tab_products.dart';
import 'add_product.dart';
import 'add_donation.dart';
import 'tab_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'volunteer_donations.dart';
import 'notifications_screen.dart';
import 'tab_leaderboard.dart';
import 'tab_lost&found.dart';
import 'add_lost_item.dart';
import 'server.dart';
import '../services/profile_service.dart';

// Chat refresh service to manage periodic updates
class ChatRefreshService {
  static final ChatRefreshService _instance = ChatRefreshService._internal();
  factory ChatRefreshService() => _instance;
  ChatRefreshService._internal();
  
  Timer? _backgroundTimer;
  Timer? _foregroundTimer;
  Timer? _activeChatTimer;
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  bool _isAppInForeground = true;
  bool _isChatScreenActive = false;
  String? _activeChatId;
  
  // Initialize the service
  void initialize() {
    _loadCurrentUser();
    _startForegroundRefresh();
    
  }

  Future<void> _loadCurrentUser() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['user'] != null) {
          await _secureStorage.write(key: 'userId', value: data['user']['_id']);
          await _secureStorage.write(key: 'userName', value: data['user']['userName']);
          await _secureStorage.write(key: 'userRole', value: data['user']['role']);
          await ProfileService.cacheUserProfile(data);
        }
      }
    } catch (e) {
      print('Error loading user: $e');
    }
  }
  
  // Notify the service when app state changes
  void setAppState(bool isInForeground) {
    if (_isAppInForeground != isInForeground) {
      _isAppInForeground = isInForeground;
      
      if (isInForeground) {
        _startForegroundRefresh();
        _stopBackgroundRefresh();
      } else {
        _stopForegroundRefresh();
        _startBackgroundRefresh();
      }
    }
  }
  
  // Notify the service when chat screen becomes active
  void setChatScreenActive(bool isActive, String? conversationId) {
    _isChatScreenActive = isActive;
    _activeChatId = isActive ? conversationId : null;
    
    if (isActive) {
      _startActiveChatRefresh(conversationId!);
    } else {
      _stopActiveChatRefresh();
    }
  }
  
  // Start foreground refresh (4-second interval)
  void _startForegroundRefresh() {
    _stopForegroundRefresh(); // Stop existing timer if any
    
    _foregroundTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshChats(isActiveRefresh: false),
    );
  }
  
  // Stop foreground refresh
  void _stopForegroundRefresh() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }
  
  // Start background refresh (10-second interval)
  void _startBackgroundRefresh() {
    _stopBackgroundRefresh(); // Stop existing timer if any
    
    _backgroundTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshChats(isActiveRefresh: false),
    );
  }
  
  // Stop background refresh
  void _stopBackgroundRefresh() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }
  
  // Start active chat refresh (1-second interval)
  void _startActiveChatRefresh(String conversationId) {
    _stopActiveChatRefresh(); // Stop existing timer if any
    
    _activeChatTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshActiveChat(conversationId),
    );
  }
  
  // Stop active chat refresh
  void _stopActiveChatRefresh() {
    _activeChatTimer?.cancel();
    _activeChatTimer = null;
  }
  
  // Refresh all chats
  Future<void> _refreshChats({bool isActiveRefresh = false}) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) return;
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      ).timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final conversations = data['conversations'];
          
          // Save to local storage
          await _secureStorage.write(
            key: 'conversations',
            value: json.encode(conversations),
          );
          
          // Update last sync timestamp
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_chat_sync', DateTime.now().toIso8601String());
        }
      }
    } catch (e) {
      print('Error in chat refresh service: $e');
    }
  }
  
  // Refresh only the active chat
  Future<void> _refreshActiveChat(String conversationId) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) return;
      
      // Get the last message ID
      final lastId = await _secureStorage.read(key: 'last_message_id_$conversationId');
      String url = '$serverUrl/api/conversations/$conversationId/messages';
      
      if (lastId != null) {
        url += '?lastId=$lastId';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final newMessages = data['messages'] ?? [];
          
          if (newMessages.isNotEmpty) {
            // Get existing messages
            final String? messagesJson = await _secureStorage.read(key: 'messages_$conversationId');
            List messages = [];
            Set processedIds = {};
            
            if (messagesJson != null) {
              messages = json.decode(messagesJson);
              processedIds = Set.from(
                messages.where((m) => m['messageId'] != null)
                    .map((m) => m['messageId'].toString())
              );
            }
            
            // Add new messages if not already processed
            bool hasNewMessages = false;
            int highestId = 0;
            for (var newMsg in newMessages) {
              if (newMsg['messageId'] != null) {
                final msgId = newMsg['messageId'];
                
                if (!processedIds.contains(msgId.toString())) {
                  messages.add(newMsg);
                  processedIds.add(msgId.toString());
                  hasNewMessages = true;
                  
                  if (msgId > highestId) {
                    highestId = msgId;
                  }
                }
              }
            }
            
            if (hasNewMessages) {
              // Sort by creation time
              messages.sort((a, b) {
                final aTime = DateTime.parse(a['createdAt']);
                final bTime = DateTime.parse(b['createdAt']);
                return aTime.compareTo(bTime);
              });
              
              // Save back to storage
              await _secureStorage.write(
                key: 'messages_$conversationId',
                value: json.encode(messages),
              );
              
              // Update last message ID
              if (highestId > 0) {
                await _secureStorage.write(
                  key: 'last_message_id_$conversationId',
                  value: highestId.toString(),
                );
              }
              
              // Update global conversation list
              _refreshChats(isActiveRefresh: true);
            }
          }
        }
      }
    } catch (e) {
      print('Error refreshing active chat: $e');
    }
  }
  
  // Clean up resources
  void dispose() {
    _stopForegroundRefresh();
    _stopBackgroundRefresh();
    _stopActiveChatRefresh();
  }
}

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  static final GlobalKey<_UserHomeScreenState> homeKey = GlobalKey<_UserHomeScreenState>();

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  
  // Only keep chat service
  final ChatRefreshService _chatRefreshService = ChatRefreshService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Timer? _notificationTimer;
  Timer? _notificationBackgroundTimer;
  Timer? _profileRefreshTimer;
  String? _lastNotificationId;
  bool _isInitialized = false;
  String? _userRole;

  // Add these variables for FAB animation
  bool _isAddButtonExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  // List of tabs displayed in the home screen
  final List<Widget> _tabs = const [
    ProductsTab(),
    LostFoundTab(),
    LeaderboardTab(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
    _loadUserRole();
    
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize all cache services
      await ProfileService.initialize();
      
      // Start the chat and notification services
      _chatRefreshService.initialize();
      await _loadLastNotificationId();
      _startNotificationRefresh();
      
      // Periodically refresh profile data in the background
      _startProfileRefresh();
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing app: $e');
    }
  }

  void _startProfileRefresh() {
    _profileRefreshTimer?.cancel();
    _profileRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshProfileData()
    );
  }

  Future<void> _refreshProfileData() async {
    try {
      await ProfileService.fetchAndUpdateProfile();
    } catch (e) {
      print('Error refreshing profile data: $e');
    }
  }

  Future<void> _loadLastNotificationId() async {
    _lastNotificationId = await _secureStorage.read(key: 'last_notification_id');
  }

  void _startNotificationRefresh() {
    // Cancel existing timers
    _notificationTimer?.cancel();
    _notificationBackgroundTimer?.cancel();

    // Start foreground refresh (10 seconds)
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 10), 
      (_) => _refreshNotifications()
    );
  }

  void _startNotificationBackgroundRefresh() {
    // Cancel existing timers
    _notificationTimer?.cancel();
    _notificationBackgroundTimer?.cancel();

    // Start background refresh (60 seconds)
    _notificationBackgroundTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshNotifications()
    );
  }

  Future<void> _refreshNotifications() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) return;

      String url = '$serverUrl/api/notifications';
      if (_lastNotificationId != null) {
        url = '$serverUrl/api/notifications/after/$_lastNotificationId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final notifications = data['notifications'] ?? [];
        
        if (notifications.isNotEmpty) {
          // Get cached notifications
          final String? notificationsJson = await _secureStorage.read(key: 'notifications');
          List existingNotifications = [];

          if (notificationsJson != null) {
            existingNotifications = json.decode(notificationsJson);
          }

          // Fix: Convert notificationId to String before comparison
          if (notifications.isNotEmpty) {
            existingNotifications.insertAll(0, notifications);

            // Get the highest notification ID
            int highestId = 0;
            for (var notification in notifications) {
              if (notification['notificationId'] != null) {
                final int notifId = int.parse(notification['notificationId'].toString());

                if (notifId > highestId) {
                  highestId = notifId;
                }
              }
            }

            _lastNotificationId = highestId.toString();

            // Save updated notifications
            await _secureStorage.write(
              key: 'notifications',
              value: json.encode(existingNotifications)
            );

            // Save last notification ID
            await _secureStorage.write(
              key: 'last_notification_id',
              value: _lastNotificationId
            );
          }
        }
      }
    } catch (e) {
      print('Error refreshing notifications: $e');
    }
  }

  Future<void> _loadUserRole() async {
    final userRole = await _secureStorage.read(key: 'userRole');
    setState(() {
      _userRole = userRole;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      _chatRefreshService.setAppState(true);
      _startNotificationRefresh(); // Start foreground refresh
      _refreshProfileData(); // Refresh profile data when app is resumed
    } else if (state == AppLifecycleState.paused) {
      _chatRefreshService.setAppState(false);
      _startNotificationBackgroundRefresh(); // Start background refresh
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _chatRefreshService.dispose();
    _notificationTimer?.cancel();
    _notificationBackgroundTimer?.cancel();
    _profileRefreshTimer?.cancel();
    super.dispose();
  }

  // Add method to toggle FAB
  void _toggleAddButton() {
    setState(() {
      _isAddButtonExpanded = !_isAddButtonExpanded;
      if (_isAddButtonExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void switchToTab(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override 
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0, // Prevents color change on scroll
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            '𝒞𝒶𝓂𝓅𝓊𝓈𝒦𝒶𝓇𝓉',
            style: TextStyle(
              color: Colors.black,
              fontSize: 30, // Increased from previous size
              fontWeight: FontWeight.w400, // Reduced from bold
            ),
          ),
          centerTitle: false,
          actions: [
            if (_userRole == 'volunteer')
              IconButton(
                icon: const Icon(Icons.volunteer_activism, color: Colors.black),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const VolunteerDonationsPage()),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.notifications, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChatListScreen()),
                );
              },
            ),
          ],
        ),
        body: _isInitialized 
          ? _tabs[_selectedIndex] 
          : const Center(child: CircularProgressIndicator(color: Colors.black)),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex >= 2 ? _selectedIndex + 1 : _selectedIndex,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: Colors.black,
            unselectedItemColor: Colors.grey,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            onTap: (index) {
              if (index == 2) {
                _showAddMenu(context);
              } else if (index > 2) {
                setState(() => _selectedIndex = index - 1);
              } else {
                setState(() => _selectedIndex = index);
              }
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: "Products",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.find_in_page),
                label: "Lost & Found",
              ),
              BottomNavigationBarItem(
                icon: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _animationController.value * pi / 2,
                      child: Icon(
                        _isAddButtonExpanded ? Icons.close : Icons.add_circle_outline,
                      ),
                    );
                  },
                ),
                label: "Add",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.leaderboard),
                label: "Leaderboard", 
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: "Profile",
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    setState(() => _isAddButtonExpanded = true);
    _animationController.forward();

    showDialog(
      context: context,
      barrierColor: Colors.black54, // Semi-transparent black background
      barrierDismissible: true,
      builder: (context) => WillPopScope(
        onWillPop: () async {
          setState(() => _isAddButtonExpanded = false);
          _animationController.reverse();
          return true;
        },
        child: Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          alignment: Alignment.bottomCenter,
          insetPadding: EdgeInsets.only(bottom: 70),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150, // Reduced from 170
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _isAddButtonExpanded = false);
                    _animationController.reverse();
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SellTab()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    minimumSize: const Size(double.infinity, 35), // Reduced from 40
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Sell Product', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 6), // Reduced from 8
              SizedBox(
                width: 150, // Reduced from 170
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _isAddButtonExpanded = false);
                    _animationController.reverse();
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddLostItemScreen()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(double.infinity, 35), // Reduced from 40
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Report Lost', style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 6), // Reduced from 8
              SizedBox(
                width: 150, // Reduced from 170
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _isAddButtonExpanded = false);
                    _animationController.reverse();
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddDonationScreen()));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 35), // Reduced from 40
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Add Donation', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // When dialog is dismissed
      setState(() => _isAddButtonExpanded = false);
      _animationController.reverse();
    });
  }
}
