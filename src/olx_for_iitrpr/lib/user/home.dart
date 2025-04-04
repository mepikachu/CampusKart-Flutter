import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_list.dart';
import 'tab_products.dart';
import 'tab_sell.dart';
import 'tab_donations.dart';
import 'tab_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications_screen.dart';

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

class _HomeScreenState extends State<UserHomeScreen> with WidgetsBindingObserver {
  final _secureStorage = const FlutterSecureStorage();
  int _selectedIndex = 0;
  
  // Create an instance of the chat refresh service
  final ChatRefreshService _chatRefreshService = ChatRefreshService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verifyAuthCookie();
    
    // Initialize the chat refresh service
    _chatRefreshService.initialize();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Update chat refresh service based on app state
    if (state == AppLifecycleState.resumed) {
      _chatRefreshService.setAppState(true);
    } else if (state == AppLifecycleState.paused) {
      _chatRefreshService.setAppState(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatRefreshService.dispose();
    super.dispose();
  }

  void switchToTab(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Future<void> _verifyAuthCookie() async {
    final authCookie = await _secureStorage.read(key: 'authCookie');
    if (authCookie == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    // Call /api/me to verify the cookie:
    final response = await http.get(
      Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie,
      },
    );
    if (response.statusCode != 200) {
      // Invalid cookie; clear it and redirect:
      await _secureStorage.delete(key: 'authCookie');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // List of four tabs displayed in the home screen.
  final List<Widget> _tabs = const [
    ProductsTab(),
    SellTab(),
    DonationsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "OLX-IITRPR",
          style: TextStyle(color: Colors.black87),
        ),
        centerTitle: false, // This aligns the title to the left
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications,
              color: Colors.black87,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.chat_bubble,
              color: Colors.black87,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ChatListScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _tabs[_selectedIndex],
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
            icon: Icon(Icons.sell),
            label: "Sell",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.volunteer_activism),
            label: "Donations",
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
