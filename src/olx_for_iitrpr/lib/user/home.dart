import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_list.dart';
import 'tab_products.dart';
import 'add_product.dart';
import 'add_donation.dart';
import 'tab_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications_screen.dart';
import 'tab_leaderboard.dart';
import 'tab_lost&found.dart';
import 'add_lost_item.dart';

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
    _startForegroundRefresh();
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
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
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
      String url = 'https://olx-for-iitrpr-backend.onrender.com/api/conversations/$conversationId/messages';
      
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

  static final GlobalKey<_HomeScreenState> homeKey = GlobalKey<_HomeScreenState>();

  @override
  State<UserHomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<UserHomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isFabExpanded = false;
  
  // Only keep chat service
  final ChatRefreshService _chatRefreshService = ChatRefreshService();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Timer? _notificationTimer;
  Timer? _notificationBackgroundTimer;
  String? _lastNotificationId;

  // List of four tabs displayed in the home screen
  final List<Widget> _tabs = const [
    ProductsTab(),
    LostFoundTab(),
    LeaderboardTab(),
    ProfileTab(),
  ];

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatRefreshService.initialize();
    _loadLastNotificationId();
    _startNotificationRefresh();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  Future<void> _loadLastNotificationId() async {
    _lastNotificationId = await _secureStorage.read(key: 'last_notification_id');
  }

  void _startNotificationRefresh() {
    // Cancel existing timers
    _notificationTimer?.cancel();
    _notificationBackgroundTimer?.cancel();

    // Start foreground refresh (4 seconds)
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 10), 
      (_) => _refreshNotifications()
    );
  }

  void _startNotificationBackgroundRefresh() {
    // Cancel existing timers
    _notificationTimer?.cancel();
    _notificationBackgroundTimer?.cancel();

    // Start background refresh (10 seconds)
    _notificationBackgroundTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshNotifications()
    );
  }

  Future<void> _refreshNotifications() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) return;

      String url = 'https://olx-for-iitrpr-backend.onrender.com/api/notifications';
      if (_lastNotificationId != null) {
        url = 'https://olx-for-iitrpr-backend.onrender.com/api/notifications/after/$_lastNotificationId';
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

  void _toggleFab() {
    setState(() {
      _isFabExpanded = !_isFabExpanded;
      if (_isFabExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      _chatRefreshService.setAppState(true);
      _startNotificationRefresh(); // Start foreground refresh
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
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "IITRPR MarketPlace",
          style: TextStyle(color: Colors.black87),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatListScreen()),
              );
            },
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat, // Change this
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16), // Add padding to match tab height
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _animation,
              child: Column(
                children: [
                  if (_isFabExpanded) ...[
                    FloatingActionButton.extended(
                      heroTag: 'lost',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddLostItemScreen()),
                        ).then((success) {
                          if (success == true) {
                            // Refresh lost items tab if needed
                            setState(() {});
                          }
                        });
                      },
                      backgroundColor: Colors.orange[600],
                      label: const Text(
                        'Report Lost Item',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.search),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'donate',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AddDonationScreen()),
                        );
                      },
                      backgroundColor: Colors.green[600],
                      label: const Text(
                        'Add Donation',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.volunteer_activism),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'sell',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SellTab()),
                        );
                      },
                      backgroundColor: Colors.blue[600],
                      label: const Text(
                        'Sell Product',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.sell),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _isFabExpanded ? Colors.red : Colors.blue[700]!,
                    _isFabExpanded ? Colors.redAccent : Colors.blue[500]!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _isFabExpanded ? 0.125 : 0,
                child: MaterialButton(
                  onPressed: _toggleFab,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  child: Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() { _selectedIndex = index; }),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Products",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.find_in_page),
            label: "Lost & Found",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: "Leaderboard",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
