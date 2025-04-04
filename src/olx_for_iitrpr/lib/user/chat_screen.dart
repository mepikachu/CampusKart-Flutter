import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'view_profile.dart';
import 'product_description.dart';
import 'product_management.dart';
import 'home.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String partnerNames;
  final String partnerId;
  final Map? initialProduct; // For "Chat with Seller"
  
  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.partnerNames,
    required this.partnerId,
    this.initialProduct,
  }) : super(key: key);

  @override
  State createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _messageInputFocusNode = FocusNode();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  
  // Access chat refresh service
  final ChatRefreshService _chatRefreshService = ChatRefreshService();
  
  List messages = [];
  List filteredMessages = []; // For search results
  Set processedMessageIds = {}; // Track processed message IDs to prevent duplicates
  bool isLoading = true;
  bool isBlocked = false;
  bool isCheckedBlocked = false;
  bool isSearching = false;
  bool showScrollToBottom = false; // State for scroll-to-bottom button
  bool _initialLoadComplete = false; // Track if initial load is complete
  bool _isInSelectionMode = false; // Track if user is selecting messages
  
  String currentUserId = '';
  String currentUserName = '';
  String? _lastFetchedMessageId; // Track last fetched message ID
  String? _lastReadMessageId; // Track last read message ID
  int _newMessagesCount = 0; // Count of new unread messages
  
  String? _highlightedMessageId;
  final Map _messageKeys = {};
  String? _swipingMessageId;
  double _messageSwipeOffset = 0.0;
  final double _replyThreshold = 60.0;
  
  // Animation controllers
  AnimationController? _swipeController;
  Animation<double>? _swipeAnimation;
  
  // Cache for product details to avoid redundant loading
  final Map<String, Map<String, dynamic>> _productCache = {};
  // Cache for product futures to prevent rebuilds and flickering
  final Map<String, Future<Map<String, dynamic>>> _productFutureCache = {};
  
  Uint8List? partnerProfilePicture;
  
  // For message selection and deletion
  List _selectedMessageIds = [];
  
  // For reply functionality
  Map? _replyingTo;
  
  // Flag to prevent multiple haptic feedback
  bool _hapticFeedbackTriggered = false;
  
  // StreamSubscription to listen for updates
  StreamSubscription? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _swipeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_swipeController!);
    
    _loadUserInfo();
    _loadLocalBlockStatus();
    _loadLastMessageId();
    _loadLastReadMessageId();
    _loadLocalMessages();
    _checkIfBlocked();
    _loadPartnerProfilePicture();
    
    // Handle initial product from "Chat with Seller"
    if (widget.initialProduct != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _replyingTo = {
            'id': widget.initialProduct!['productId'],
            'type': 'product',
            'text': widget.initialProduct!['name'] ?? 'Product',
          };
        });
        
        // Focus the text field for typing
        FocusScope.of(context).requestFocus(_messageInputFocusNode);
      });
    }
    
    // Notify the refresh service that the chat screen is active
    _chatRefreshService.setChatScreenActive(true, widget.conversationId);
    
    // Add scroll listener for showing scroll-to-bottom button and tracking read messages
    _scrollController.addListener(_handleScroll);
    
    // Setup periodic check for new messages from the service
    _setupRefreshListener();
  }
  
  void _setupRefreshListener() {
    // Check for message updates every 500ms
    _refreshSubscription = Stream.periodic(const Duration(milliseconds: 500)).listen((_) async {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString('last_message_sync_${widget.conversationId}');
      
      if (lastSync != null) {
        final lastSyncTime = DateTime.parse(lastSync);
        final lastChecked = prefs.getString('last_message_checked_${widget.conversationId}');
        
        if (lastChecked == null || 
            DateTime.parse(lastChecked).isBefore(lastSyncTime)) {
          // New messages available, refresh
          await _fetchNewMessages();
          // Update last checked timestamp
          await prefs.setString(
            'last_message_checked_${widget.conversationId}', 
            DateTime.now().toIso8601String()
          );
        }
      }
    });
  }

  @override
  void dispose() {
    // Notify the refresh service that the chat screen is no longer active
    _chatRefreshService.setChatScreenActive(false, null);
    
    _refreshSubscription?.cancel();
    _swipeController?.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _messageInputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Load last read message ID from storage
  Future<void> _loadLastReadMessageId() async {
    try {
      final json = await _secureStorage.read(key: 'lastReadMessageIds');
      if (json != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(jsonDecode(json));
        if (data.containsKey(widget.conversationId)) {
          setState(() {
            _lastReadMessageId = data[widget.conversationId];
          });
        }
      }
    } catch (e) {
      print('Error loading last read message ID: $e');
    }
  }

  // Save last read message ID to storage in a format usable by both screens
  Future<void> _saveLastReadMessageId(String messageId) async {
    try {
      // Load existing data
      final json = await _secureStorage.read(key: 'lastReadMessageIds');
      Map<String, dynamic> data = {};
      
      if (json != null) {
        data = Map<String, dynamic>.from(jsonDecode(json));
      }
      
      // Update with new message ID
      data[widget.conversationId] = messageId;
      _lastReadMessageId = messageId;
      
      // Save back
      await _secureStorage.write(
        key: 'lastReadMessageIds',
        value: jsonEncode(data),
      );
      
      // Update message counters
      setState(() {
        _newMessagesCount = 0;
      });
    } catch (e) {
      print('Error saving last read message ID: $e');
    }
  }

  // Mark messages as read up to a specific message
  void _markMessagesAsRead() {
    if (messages.isEmpty) return;
    
    try {
      // Find the newest visible message
      if (_scrollController.hasClients &&
          _scrollController.position.pixels <= _scrollController.position.minScrollExtent + 100) {
        
        // We're at or near the bottom, mark latest message as read
        final latestMessage = messages.last;
        final latestMessageId = latestMessage['messageId'].toString();
        
        if (_lastReadMessageId != latestMessageId) {
          _saveLastReadMessageId(latestMessageId);
        }
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Load last message ID from storage
  Future<void> _loadLastMessageId() async {
    try {
      final lastId = await _secureStorage.read(key: 'last_message_id_${widget.conversationId}');
      if (lastId != null) {
        _lastFetchedMessageId = lastId;
      }
    } catch (e) {
      print('Error loading last message ID: $e');
    }
  }

  // Save last message ID to storage
  Future<void> _saveLastMessageId(String messageId) async {
    try {
      await _secureStorage.write(key: 'last_message_id_${widget.conversationId}', value: messageId);
      _lastFetchedMessageId = messageId;
    } catch (e) {
      print('Error saving last message ID: $e');
    }
  }

  // Load partner's profile picture
  Future<void> _loadPartnerProfilePicture() async {
    try {
      // First check if we have it cached
      final cachedPicture = await _secureStorage.read(key: 'profile_pic_${widget.partnerId}');
      if (cachedPicture != null) {
        if (mounted) {
          setState(() {
            partnerProfilePicture = base64Decode(cachedPicture);
          });
        }
        return;
      }

      // If not in cache, fetch from server
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/profile-picture/${widget.partnerId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        if (response.headers['content-type']?.contains('application/json') != true) {
          // This is binary data (image)
          if (mounted) {
            setState(() {
              partnerProfilePicture = response.bodyBytes;
            });
          }
          
          // Cache the profile picture
          await _secureStorage.write(
            key: 'profile_pic_${widget.partnerId}',
            value: base64Encode(response.bodyBytes),
          );
        }
      }
    } catch (e) {
      print('Error loading partner profile picture: $e');
    }
  }

  // Navigate to view user profile
  void _navigateToUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(userId: widget.partnerId),
      ),
    );
  }

  // Scroll listener for showing scroll-to-bottom button and tracking read messages
  void _handleScroll() {
    if (_scrollController.hasClients) {
      final bool wasAtBottom = !showScrollToBottom;
      
      setState(() {
        showScrollToBottom = _scrollController.position.pixels > 300;
      });
      
      // If we've scrolled to the bottom, mark messages as read
      if (wasAtBottom && !showScrollToBottom) {
        _markMessagesAsRead();
        setState(() {
          _newMessagesCount = 0;
        });
      }
    }
  }

  // Scroll to bottom function
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      
      // After scrolling to bottom, mark messages as read and reset counter
      setState(() {
        _newMessagesCount = 0;
      });
      _markMessagesAsRead();
    }
  }

  // Format date for header display
  String _formatDateForHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);
    
    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (today.difference(messageDate).inDays < 7) {
      // Within the last week - show day of week
      return DateFormat('EEEE').format(date); // e.g. "Monday"
    } else {
      // Older messages - show full date
      return DateFormat('MMMM d, yyyy').format(date); // e.g. "March 15, 2025"
    }
  }

  // Load block status from local storage
  Future<void> _loadLocalBlockStatus() async {
    try {
      final String? blockedStatus = await _secureStorage.read(key: 'blocked_${widget.partnerId}');
      if (blockedStatus == 'true') {
        setState(() {
          isBlocked = true;
          isCheckedBlocked = true;
        });
      }
    } catch (e) {
      print('Error loading local block status: $e');
    }
  }

  // Save block status to local storage
  Future<void> _saveBlockStatus(bool blocked) async {
    try {
      await _secureStorage.write(
        key: 'blocked_${widget.partnerId}',
        value: blocked ? 'true' : 'false'
      );
    } catch (e) {
      print('Error saving block status: $e');
    }
  }

  // Reset swipe with animation
  void _resetSwipe() {
    if (_swipingMessageId != null) {
      _swipeController?.reverse().then((_) {
        setState(() {
          _swipingMessageId = null;
          _messageSwipeOffset = 0.0;
          _hapticFeedbackTriggered = false;
        });
      });
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      String? id = await _secureStorage.read(key: 'userId');
      final name = await _secureStorage.read(key: 'userName');
      
      if (id == null || id.isEmpty) {
        final authCookie = await _secureStorage.read(key: 'authCookie');
        final response = await http.get(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/me'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['user'] != null) {
            id = data['user']['_id'];
            await _secureStorage.write(key: 'userId', value: id);
          }
        }
      }
      
      if (mounted) {
        setState(() {
          if (id != null) currentUserId = id;
          if (name != null) currentUserName = name;
        });
      }
    } catch (e) {
      print('Error loading user info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading user information')),
        );
      }
    }
  }

  Future<void> _checkIfBlocked() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/blocked'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final List blockedUsers = json.decode(response.body);
        final bool wasBlocked = isBlocked;
        bool serverBlocked = false;
        
        for (var user in blockedUsers) {
          if (user['blocked'] != null) {
            String blockedId = '';
            if (user['blocked'] is String) {
              blockedId = user['blocked'];
            } else if (user['blocked'] is Map && user['blocked']['_id'] != null) {
              blockedId = user['blocked']['_id'];
            }
            
            if (blockedId == widget.partnerId) {
              serverBlocked = true;
              break;
            }
          }
        }
        
        if (mounted) {
          setState(() {
            isBlocked = serverBlocked;
            isCheckedBlocked = true;
          });
          _saveBlockStatus(serverBlocked);
          
          if (wasBlocked != serverBlocked) {
            _fetchMessages();
          }
        }
      }
    } catch (e) {
      print('Error checking block status: $e');
    }
  }

  // Toggle message selection for deletion
  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isInSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
        _isInSelectionMode = true;
      }
    });
  }

  // Cancel selection mode
  void _cancelSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _isInSelectionMode = false;
    });
  }

  // Load messages from local storage
  Future<void> _loadLocalMessages() async {
    try {
      final messagesJson = await _secureStorage.read(key: 'messages_${widget.conversationId}');
      if (messagesJson != null) {
        final loadedMessages = json.decode(messagesJson);
        
        // Initialize the set of processed message IDs
        Set localProcessedIds = {};
        for (var msg in loadedMessages) {
          if (msg['messageId'] != null) {
            localProcessedIds.add(msg['messageId'].toString());
          }
        }
        
        if (mounted) {
          setState(() {
            messages = loadedMessages;
            filteredMessages = messages;
            processedMessageIds = localProcessedIds;
            isLoading = false;
          });
        }
        
        // After loading local messages, fetch from server to get latest
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchMessages();
          _initialLoadComplete = true;
          
          if (_scrollController.hasClients && messages.isNotEmpty) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
            
            // Mark messages as read when loaded and scrolled to bottom
            _markMessagesAsRead();
          }
        });
      } else {
        _fetchMessages();
        _initialLoadComplete = true;
      }
    } catch (e) {
      print('Error loading local messages: $e');
      _fetchMessages();
      _initialLoadComplete = true;
    }
  }

  // Save messages to local storage
  Future<void> _saveMessagesLocally() async {
    try {
      await _secureStorage.write(
        key: 'messages_${widget.conversationId}',
        value: json.encode(messages),
      );
      
      // Update last sync timestamp for both screens
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_message_sync_${widget.conversationId}', 
        DateTime.now().toIso8601String()
      );
    } catch (e) {
      print('Error saving messages locally: $e');
    }
  }

  // Delete selected messages (locally only)
  Future<void> _deleteSelectedMessages() async {
    try {
      // Remove deleted messages from the local list
      setState(() {
        messages = messages.where((msg) =>
          !_selectedMessageIds.contains(msg['messageId'].toString())
        ).toList();
        
        if (!isSearching) {
          filteredMessages = messages;
        } else {
          _filterMessages(_searchController.text);
        }
        
        _isInSelectionMode = false;
        _selectedMessageIds.clear();
      });
      
      // Save updated messages locally
      await _saveMessagesLocally();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Messages deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting messages: $e')),
      );
    }
  }

  // Clear all messages in the chat (locally only)
  Future<void> _clearChat() async {
    try {
      // Confirm with the user
      final confirmed = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear Chat'),
          content: const Text('Are you sure you want to clear all messages in this chat?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Clear'),
            ),
          ],
        ),
      ) ?? false;
      
      if (!confirmed) return;
      
      setState(() {
        // Only remove messages sent by the current user
        messages = messages.where((msg) =>
          msg['sender'] != currentUserId
        ).toList();
        
        if (!isSearching) {
          filteredMessages = messages;
        } else {
          _filterMessages(_searchController.text);
        }
      });
      
      await _saveMessagesLocally();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat cleared successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing chat: $e')),
      );
    }
  }

  GlobalKey _getKeyForMessage(String messageId) {
    if (!_messageKeys.containsKey(messageId)) {
      _messageKeys[messageId] = GlobalKey();
    }
    return _messageKeys[messageId]!;
  }

  void _scrollToMessage(String messageId) {
    try {
      setState(() {
        _highlightedMessageId = messageId;
      });
      
      final messageIndex = messages.indexWhere((m) =>
        m['messageId'] != null && m['messageId'].toString() == messageId);
      
      if (messageIndex != -1) {
        final scrollIndex = messages.length - 1 - messageIndex;
        
        _scrollController.animateTo(
          scrollIndex * 75.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        
        Future.delayed(const Duration(milliseconds: 200), () {
          final key = _getKeyForMessage(messageId);
          if (key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 300),
              alignment: 0.5,
            );
          }
        });
        
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _highlightedMessageId = null;
            });
          }
        });
      }
    } catch (e) {
      print('Error scrolling to message: $e');
    }
  }

  // Navigate to product when clicking on product in messages
  void _navigateToProduct(String productId) async {
    try {
      // First check if we have cached product details
      if (_productCache.containsKey(productId)) {
        final product = _productCache[productId];
        final sellerId = product!['seller'] is String ?
          product['seller'] :
          product['seller']['_id'];
        
        if (sellerId == currentUserId) {
          // Navigate to seller management if current user is the seller
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SellerOfferManagementScreen(
                product: product,
              ),
            ),
          );
        } else {
          // Navigate to product details if someone else is the seller
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                product: product,
              ),
            ),
          );
        }
        return;
      }
      
      // If not cached, fetch from server
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/$productId'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['product'] != null) {
          final product = data['product'];
          // Cache the product
          _productCache[productId] = product;
          
          final sellerId = product['seller'] is String ?
            product['seller'] :
            product['seller']['_id'];
          
          if (sellerId == currentUserId) {
            // Navigate to seller management
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SellerOfferManagementScreen(
                  product: product,
                ),
              ),
            );
          } else {
            // Navigate to product details
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductDetailsScreen(
                  product: product,
                ),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product details could not be loaded')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product not available')),
        );
      }
    } catch (e) {
      print('Error navigating to product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load product details')),
      );
    }
  }

  // Fetch messages from server with message ID tracking
  Future<void> _fetchMessages() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      String url = 'https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages';
      
      // Use last message ID for efficient fetching
      if (_lastFetchedMessageId != null) {
        url += '?lastId=$_lastFetchedMessageId';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Set loading to false regardless of whether there are messages
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        
        if (data['success']) {
          final List newMessages = data['messages'] ?? [];
          
          if (newMessages.isNotEmpty) {
            // Find highest message ID
            int highestId = 0;
            List messagesToAdd = [];
            
            for (var newMsg in newMessages) {
              if (newMsg['messageId'] != null) {
                final msgId = newMsg['messageId'];
                
                if (!processedMessageIds.contains(msgId.toString())) {
                  messagesToAdd.add(newMsg);
                  processedMessageIds.add(msgId.toString());
                  
                  if (msgId > highestId) {
                    highestId = msgId;
                  }
                }
              }
            }
            
            if (messagesToAdd.isNotEmpty && mounted) {
              // Check if user is at bottom before adding messages
              bool isAtBottom = false;
              
              if (_scrollController.hasClients) {
                isAtBottom = _scrollController.position.pixels <= 10;
              } else {
                isAtBottom = true; // If no scroll position yet, assume at bottom
              }
              
              setState(() {
                messages = [...messages, ...messagesToAdd];
                
                // Sort messages by creation time
                messages.sort((a, b) {
                  final aTime = DateTime.parse(a['createdAt']);
                  final bTime = DateTime.parse(b['createdAt']);
                  return aTime.compareTo(bTime);
                });
                
                if (!isSearching) {
                  filteredMessages = messages;
                } else {
                  _filterMessages(_searchController.text);
                }
                
                // If not at bottom, increment new messages count
                if (!isAtBottom) {
                  _newMessagesCount += messagesToAdd.length;
                }
              });
              
              if (highestId > 0) {
                await _saveLastMessageId(highestId.toString());
              }
              
              // If at bottom, mark messages as read
              if (isAtBottom && messages.isNotEmpty) {
                final latestMessageId = messages.last['messageId'].toString();
                await _saveLastReadMessageId(latestMessageId);
              }
              
              await _saveMessagesLocally();
            }
          }
        }
      } else {
        // Set loading to false on error
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching messages: $e');
      // Set loading to false on error
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Fetch only new messages incrementally
  Future<void> _fetchNewMessages() async {
    try {
      if (_lastFetchedMessageId == null) return;
      
      final authCookie = await _secureStorage.read(key: 'authCookie');
      String url = 'https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages?lastId=$_lastFetchedMessageId';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success']) {
          final List newMessages = data['messages'] ?? [];
          
          if (newMessages.isNotEmpty) {
            // Find highest message ID
            int highestId = 0;
            List messagesToAdd = [];
            
            for (var newMsg in newMessages) {
              if (newMsg['messageId'] != null) {
                final msgId = newMsg['messageId'];
                
                if (!processedMessageIds.contains(msgId.toString())) {
                  messagesToAdd.add(newMsg);
                  processedMessageIds.add(msgId.toString());
                  
                  if (msgId > highestId) {
                    highestId = msgId;
                  }
                }
              }
            }
            
            if (messagesToAdd.isNotEmpty && mounted) {
              // Check if user is at bottom before adding new messages
              bool isAtBottom = false;
              
              if (_scrollController.hasClients) {
                isAtBottom = _scrollController.position.pixels <= 10;
              }
              
              setState(() {
                messages = [...messages, ...messagesToAdd];
                
                // Sort messages by creation time
                messages.sort((a, b) {
                  final aTime = DateTime.parse(a['createdAt']);
                  final bTime = DateTime.parse(b['createdAt']);
                  return aTime.compareTo(bTime);
                });
                
                if (!isSearching) {
                  filteredMessages = messages;
                } else {
                  _filterMessages(_searchController.text);
                }
                
                // If not at bottom, increment new messages count
                if (!isAtBottom) {
                  _newMessagesCount += messagesToAdd.length;
                }
              });
              
              if (highestId > 0) {
                await _saveLastMessageId(highestId.toString());
              }
              
              // If at bottom, mark messages as read
              if (isAtBottom && messages.isNotEmpty) {
                final latestMessageId = messages.last['messageId'].toString();
                await _saveLastReadMessageId(latestMessageId);
              }
              
              await _saveMessagesLocally();
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching new messages: $e');
    }
  }

  // Send a message
  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;
    
    _messageController.clear();
    
    // Create a temporary message with a temporary ID
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    Map tempMessage = {
      'messageId': tempId,
      'sender': currentUserId,
      'text': messageText,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'pending'
    };
    
    // Add replyTo information if replying to something
    if (_replyingTo != null) {
      tempMessage['replyTo'] = {
        'id': _replyingTo!['id'],
        'type': _replyingTo!['type']
      };
    }
    
    // Store replyTo data for the API call
    final replyToData = _replyingTo;
    
    setState(() {
      // Set isLoading to false if this is the first message
      if (isLoading) {
        isLoading = false;
      }
      
      messages = [...messages, tempMessage];
      processedMessageIds.add(tempId);
      
      if (!isSearching) {
        filteredMessages = messages;
      } else {
        _filterMessages(_searchController.text);
      }
      
      _replyingTo = null;
    });
    
    // Scroll to bottom to show the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    
    // Save to local storage with pending status
    await _saveMessagesLocally();
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Prepare API call parameters
      final Map requestBody = {
        'text': messageText,
        'tempId': tempId,
      };
      
      // Add reply data if it exists
      if (replyToData != null) {
        requestBody['replyTo'] = replyToData['id'];
        requestBody['replyType'] = replyToData['type'];
      }
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success']) {
          // Update the temporary message with the server's message ID
          final serverMessageId = data['messageId'];
          
          if (mounted) {
            setState(() {
              final index = messages.indexWhere((m) =>
                m['messageId'] == tempId
              );
              
              if (index != -1) {
                messages[index]['status'] = 'sent';
                messages[index]['messageId'] = serverMessageId;
                
                // Also update in filtered messages if present
                final filteredIndex = filteredMessages.indexWhere((m) =>
                  m['messageId'] == tempId
                );
                
                if (filteredIndex != -1) {
                  filteredMessages[filteredIndex]['status'] = 'sent';
                  filteredMessages[filteredIndex]['messageId'] = serverMessageId;
                }
              }
            });
          }
          
          // Update processed message IDs
          processedMessageIds.remove(tempId);
          processedMessageIds.add(serverMessageId.toString());
          
          // Save the last message ID
          await _saveLastMessageId(serverMessageId.toString());
          
          // Also mark as read since user is sending it
          await _saveLastReadMessageId(serverMessageId.toString());
          
          // Save updated messages
          await _saveMessagesLocally();
        } else {
          _markMessageAsFailed(tempId);
        }
      } else {
        _markMessageAsFailed(tempId);
      }
    } catch (e) {
      print('Error sending message: $e');
      _markMessageAsFailed(tempId);
    }
  }

  // Mark a message as failed
  void _markMessageAsFailed(String tempId) {
    if (mounted) {
      setState(() {
        final index = messages.indexWhere((m) => m['messageId'] == tempId);
        
        if (index != -1) {
          messages[index]['status'] = 'failed';
          
          // Also update in filtered messages if present
          final filteredIndex = filteredMessages.indexWhere((m) => m['messageId'] == tempId);
          
          if (filteredIndex != -1) {
            filteredMessages[filteredIndex]['status'] = 'failed';
          }
        }
      });
      
      _saveMessagesLocally();
    }
  }

  // Retry sending a failed message
  Future<void> _retryFailedMessage(dynamic failedMessage) async {
    final failedMessageId = failedMessage['messageId'];
    final messageText = failedMessage['text'];
    final replyTo = failedMessage['replyTo'];
    
    // Update status to pending
    setState(() {
      final index = messages.indexWhere((m) => m['messageId'] == failedMessageId);
      
      if (index != -1) {
        messages[index]['status'] = 'pending';
        
        // Also update in filtered messages if present
        final filteredIndex = filteredMessages.indexWhere((m) => m['messageId'] == failedMessageId);
        
        if (filteredIndex != -1) {
          filteredMessages[filteredIndex]['status'] = 'pending';
        }
      }
    });
    
    // Save to show pending status
    await _saveMessagesLocally();
    
    // Try sending again
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Prepare request body
      final Map requestBody = {
        'text': messageText,
        'tempId': failedMessageId,
      };
      
      // Add reply data if it exists
      if (replyTo != null) {
        requestBody['replyTo'] = replyTo['id'];
        requestBody['replyType'] = replyTo['type'];
      }
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success']) {
          // Update the message with the server's message ID
          final serverMessageId = data['messageId'];
          
          if (mounted) {
            setState(() {
              final index = messages.indexWhere((m) => m['messageId'] == failedMessageId);
              
              if (index != -1) {
                messages[index]['status'] = 'sent';
                messages[index]['messageId'] = serverMessageId;
                
                // Also update in filtered messages if present
                final filteredIndex = filteredMessages.indexWhere((m) => m['messageId'] == failedMessageId);
                
                if (filteredIndex != -1) {
                  filteredMessages[filteredIndex]['status'] = 'sent';
                  filteredMessages[filteredIndex]['messageId'] = serverMessageId;
                }
              }
            });
          }
          
          // Update processed message IDs
          processedMessageIds.remove(failedMessageId);
          processedMessageIds.add(serverMessageId.toString());
          
          // Save the last message ID
          await _saveLastMessageId(serverMessageId.toString());
          
          // Save updated messages
          await _saveMessagesLocally();
        } else {
          _markMessageAsFailed(failedMessageId);
        }
      } else {
        _markMessageAsFailed(failedMessageId);
      }
    } catch (e) {
      print('Error retrying message: $e');
      _markMessageAsFailed(failedMessageId);
    }
  }

  // Handle reply to a message
  void _handleReply(dynamic message) {
    setState(() {
      _replyingTo = {
        'id': message['messageId'],
        'type': 'message',
        'text': message['text'],
      };
    });
    
    FocusScope.of(context).requestFocus(_messageInputFocusNode);
  }

  // Filter messages for search
  void _filterMessages(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredMessages = messages;
      });
      return;
    }
    
    final lowercaseQuery = query.toLowerCase();
    
    setState(() {
      filteredMessages = messages.where((message) {
        if (message['text'] == null) return false;
        return message['text'].toString().toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

  // Toggle search mode
  void _toggleSearchMode() {
    setState(() {
      isSearching = !isSearching;
      
      if (!isSearching) {
        _searchController.clear();
        filteredMessages = messages;
      }
    });
  }

  // Block user
  Future<void> _blockUser() async {
    bool confirmed = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Block User'),
          content: Text('Are you sure you want to block ${widget.partnerNames}?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text('Block'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirmed) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/block/${widget.partnerId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() {
          isBlocked = true;
        });
        
        await _saveBlockStatus(true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User blocked successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to block user')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Unblock user
  Future<void> _unblockUser() async {
    bool confirmed = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Unblock User'),
          content: Text('Are you sure you want to unblock ${widget.partnerNames}?'),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text('Unblock'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirmed) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.delete(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/unblock/${widget.partnerId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() {
          isBlocked = false;
        });
        
        await _saveBlockStatus(false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User unblocked successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unblock user')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _getSenderNameForReply() {
    try {
      if (_replyingTo != null && _replyingTo!['type'] == 'product') {
        return 'Product';
      }
      
      final replyIdString = _replyingTo!['id'].toString();
      final originalMessage = messages.firstWhere(
        (m) => m['messageId'] != null && m['messageId'].toString() == replyIdString,
        orElse: () => {'sender': null},
      );
      
      bool isOriginalSenderMe = false;
      if (originalMessage['sender'] != null) {
        if (originalMessage['sender'] is String) {
          isOriginalSenderMe = originalMessage['sender'].toString() == currentUserId.toString();
        } else if (originalMessage['sender'] is Map && originalMessage['sender']['_id'] != null) {
          isOriginalSenderMe = originalMessage['sender']['_id'].toString() == currentUserId.toString();
        }
      }
      
      return isOriginalSenderMe ? 'You' : widget.partnerNames;
    } catch (e) {
      print('Error determining sender name: $e');
      return 'Unknown';
    }
  }

  // Helper function to fetch product details with caching to prevent flickering
  Future<Map<String, dynamic>> _fetchProductDetails(String productId) async {
    // Return the cached Future if it exists to prevent rebuilding the widget
    if (_productFutureCache.containsKey(productId)) {
      return _productFutureCache[productId]!;
    }
    
    // Create a new Future and cache it before executing
    final Future<Map<String, dynamic>> future = _fetchProductDetailsFromSources(productId);
    _productFutureCache[productId] = future;
    return future;
  }

  // Helper method that actually does the fetching
  Future<Map<String, dynamic>> _fetchProductDetailsFromSources(String productId) async {
    // First check our in-memory cache
    if (_productCache.containsKey(productId)) {
      return _productCache[productId]!;
    }
    
    // Then check local storage cache
    final cachedData = await _secureStorage.read(key: 'product_${productId}');
    if (cachedData != null) {
      final product = json.decode(cachedData);
      _productCache[productId] = product; // Update in-memory cache
      return product;
    }
    
    // Fetch from server if not in any cache
    final authCookie = await _secureStorage.read(key: 'authCookie');
    final response = await http.get(
      Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/$productId'),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] && data['product'] != null) {
        // Extract essential details
        final product = {
          'name': data['product']['name'],
          'price': data['product']['price'],
          'seller': data['product']['seller'],
          'imageUrl': data['product']['images']?.isNotEmpty == true
            ? data['product']['images'][0]['data']
            : null,
        };
        
        // Cache the product details
        await _secureStorage.write(key: 'product_${productId}', value: json.encode(product));
        _productCache[productId] = product; // Update in-memory cache
        return product;
      }
    }
    
    throw Exception('Failed to load product details');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isInSelectionMode
        ? _buildSelectionAppBar()
        : isSearching
          ? _buildSearchAppBar()
          : _buildRegularAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Start the conversation!',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: filteredMessages.length,
                        // Add findChildIndexCallback for better performance with reversed list
                        findChildIndexCallback: (key) {
                          if (key is ValueKey) {
                            final String messageId = key.value;
                            return filteredMessages.indexWhere((msg) =>
                              msg['messageId'].toString() == messageId
                            );
                          }
                          return null;
                        },
                        itemBuilder: (context, index) {
                          try {
                            final int adjustedIndex = filteredMessages.length - 1 - index;
                            if (adjustedIndex < 0 || adjustedIndex >= filteredMessages.length) {
                              return SizedBox.shrink();
                            }
                            
                            final message = filteredMessages[adjustedIndex];
                            final messageId = message['messageId'].toString();
                            final bool isMe = message['sender'] == currentUserId;
                            final double offset = _swipingMessageId == messageId ? _messageSwipeOffset : 0.0;
                            
                            // Show date header if needed
                            final bool showDateHeader = _shouldShowDateHeader(adjustedIndex);
                            final String dateHeaderText = showDateHeader
                              ? _formatDateForHeader(DateTime.parse(message['createdAt']))
                              : '';
                            
                            return Column(
                              children: [
                                if (showDateHeader)
                                  _buildDateHeader(dateHeaderText),
                                
                                // Use a key for each message to maintain identity during rebuilds
                                Container(
                                  key: ValueKey(messageId),
                                  width: double.infinity, // Full width container
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent, // Important for full width detection
                                    onLongPress: () => _toggleMessageSelection(messageId),
                                    onTap: () {
                                      if (_isInSelectionMode) {
                                        _toggleMessageSelection(messageId);
                                      }
                                    },
                                    onHorizontalDragStart: (details) {
                                      // Allow swiping for all messages in non-selection mode
                                      if (!_isInSelectionMode) {
                                        setState(() {
                                          _swipingMessageId = messageId;
                                          _messageSwipeOffset = 0.0;
                                          _hapticFeedbackTriggered = false;
                                          _swipeController!.reset();
                                        });
                                      }
                                    },
                                    onHorizontalDragUpdate: (details) {
                                      if (_swipingMessageId == messageId) {
                                        setState(() {
                                          _messageSwipeOffset += details.delta.dx;
                                          
                                          if (_messageSwipeOffset > 100) {
                                            _messageSwipeOffset = 100;
                                          } else if (_messageSwipeOffset < 0) {
                                            _messageSwipeOffset = 0;
                                          }
                                          
                                          // Update animation value based on swipe offset
                                          _swipeController!.value = _messageSwipeOffset / 100;
                                          
                                          // Add haptic feedback when crossing the reply threshold
                                          if (_messageSwipeOffset >= _replyThreshold && !_hapticFeedbackTriggered) {
                                            HapticFeedback.mediumImpact();
                                            _hapticFeedbackTriggered = true;
                                          }
                                        });
                                      }
                                    },
                                    onHorizontalDragEnd: (details) {
                                      if (_swipingMessageId == messageId) {
                                        if (_messageSwipeOffset >= _replyThreshold) {
                                          _handleReply(message);
                                        }
                                        _resetSwipe();
                                      }
                                    },
                                    onHorizontalDragCancel: () {
                                      if (_swipingMessageId == messageId) {
                                        _resetSwipe();
                                      }
                                    },
                                    child: Stack(
                                      children: [
                                        // Message alignment
                                        Row(
                                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                          children: [
                                            AnimatedContainer(
                                              duration: const Duration(milliseconds: 50),
                                              transform: Matrix4.translationValues(offset, 0, 0),
                                              child: _buildMessageItem(message, isMe),
                                            ),
                                          ],
                                        ),
                                        // Swipe arrow indicator with animation
                                        if (_swipingMessageId == messageId && offset > 0)
                                          Positioned(
                                            left: 10,
                                            top: 0,
                                            bottom: 0,
                                            child: FadeTransition(
                                              opacity: _swipeAnimation as Animation<double>,
                                              child: Center(
                                                child: Container(
                                                  padding: EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.blue.withOpacity(_swipeController!.value * 0.2),
                                                  ),
                                                  child: Transform.scale(
                                                    scale: 0.5 + (_swipeController!.value * 0.5),
                                                    child: const Icon(
                                                      Icons.reply,
                                                      color: Colors.blue,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Selection indicator
                                        if (_isInSelectionMode)
                                          Positioned(
                                            top: 0,
                                            left: isMe ? null : 0,
                                            right: isMe ? 0 : null,
                                            child: Container(
                                              padding: EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: _selectedMessageIds.contains(messageId)
                                                  ? Colors.blue
                                                  : Colors.white,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.blue),
                                              ),
                                              child: Icon(
                                                Icons.check,
                                                size: 16,
                                                color: _selectedMessageIds.contains(messageId)
                                                  ? Colors.white
                                                  : Colors.transparent,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } catch (e) {
                            print('Error building message at index $index: $e');
                            return Container(height: 0);
                          }
                        },
                      ),
              ),
              if (isBlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _unblockUser,
                    child: Text('Unblock User'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.only(left: 8, right: 8, top: 0, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25.0),
                            color: const Color.fromARGB(255, 255, 255, 255),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_replyingTo != null)
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(25.0),
                                      topRight: Radius.circular(25.0),
                                    ),
                                    color: Colors.white,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 0),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(25.0),
                                            topRight: Radius.circular(25.0),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 3,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: _replyingTo!['type'] == 'product' ? Colors.green : Colors.blue,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Show "Product" instead of sender name for product replies
                                                  Text(
                                                    _replyingTo!['type'] == 'product' ? 'Product' : _getSenderNameForReply(),
                                                    style: TextStyle(
                                                      color: _replyingTo!['type'] == 'product' ? Colors.green : Colors.blue,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  // For product replies, display the product details
                                                  if (_replyingTo!['type'] == 'product')
                                                    _buildProductReplyContent(_replyingTo!['id'])
                                                  else
                                                    Text(
                                                      _replyingTo!['text'] ?? "",
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, size: 16),
                                              onPressed: () {
                                                setState(() {
                                                  _replyingTo = null;
                                                });
                                              },
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(maxWidth: 24, maxHeight: 24),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                                child: TextField(
                                  controller: _messageController,
                                  focusNode: _messageInputFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Type a message...',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.only(left: 8, right: 8, top: 0, bottom: 0),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                  maxLines: null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue[600],
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white,
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // Scroll to bottom button with unread count
          if (showScrollToBottom)
            Positioned(
              right: 16,
              bottom: 80,
              child: Stack(
                children: [
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.blue.shade100,
                    child: Icon(
                      Icons.arrow_downward,
                      color: Colors.blue.shade800,
                    ),
                    onPressed: _scrollToBottom,
                  ),
                  if (_newMessagesCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          _newMessagesCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Special widget for product reply in the reply box to prevent flickering
  Widget _buildProductReplyContent(String productId) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchProductDetails(productId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text(
            "Loading product...",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          );
        }
        
        if (snapshot.hasData) {
          return Text(
            snapshot.data!['name'] ?? "Product",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          );
        }
        
        return Text(
          "Product",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12),
        );
      },
    );
  }

  // Build the regular app bar
  PreferredSizeWidget _buildRegularAppBar() {
    return AppBar(
      automaticallyImplyLeading: false, // Hide default back button
      leadingWidth: 40, // Reduced width for back button
      leading: IconButton( // Separated back button
        icon: Icon(Icons.arrow_back),
        padding: EdgeInsets.only(left: 8), // Reduce left padding
        constraints: BoxConstraints(),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: InkWell( // Separated profile section
        onTap: _navigateToUserProfile,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: partnerProfilePicture != null
                ? MemoryImage(partnerProfilePicture!)
                : null,
              child: partnerProfilePicture == null
                ? Text(
                    widget.partnerNames.isNotEmpty
                      ? widget.partnerNames[0].toUpperCase()
                      : '?',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.partnerNames,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search),
          onPressed: _toggleSearchMode,
        ),
        PopupMenuButton(
          onSelected: (value) {
            switch (value) {
              case 'block':
                if (isBlocked) {
                  _unblockUser();
                } else {
                  _blockUser();
                }
                break;
              case 'clear_chat':
                _clearChat();
                break;
              case 'view_profile':
                _navigateToUserProfile();
                break;
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry>[
            const PopupMenuItem(
              value: 'view_profile',
              child: Row(
                children: [
                  Icon(Icons.person, size: 18),
                  SizedBox(width: 8),
                  Text('View Profile'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block',
              child: Row(
                children: [
                  Icon(
                    isBlocked ? Icons.lock_open : Icons.block,
                    size: 18
                  ),
                  SizedBox(width: 8),
                  Text(isBlocked ? 'Unblock User' : 'Block User'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear_chat',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep, size: 18),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Build the search app bar
  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Colors.blue),
        onPressed: _toggleSearchMode,
      ),
      title: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search messages...',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade200,
          ),
          onChanged: _filterMessages,
        ),
      ),
    );
  }

  // Build the selection app bar (shown when selecting messages)
  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: _cancelSelection,
      ),
      title: Text('${_selectedMessageIds.length} selected'),
      actions: [
        IconButton(
          icon: Icon(Icons.delete),
          onPressed: _selectedMessageIds.isNotEmpty ? _deleteSelectedMessages : null,
        ),
      ],
    );
  }

  // Build a message item
  Widget _buildMessageItem(dynamic message, bool isMe) {
    try {
      final messageTime = DateFormat('HH:mm').format(
        DateTime.parse(message['createdAt']),
      );
      
      final bool isPending = message['status'] == 'pending';
      final bool isFailed = message['status'] == 'failed';
      final bool isHighlighted = message['messageId'] != null &&
        message['messageId'].toString() == _highlightedMessageId;
      
      // Check if this message is replying to a product
      final bool replyingToProduct = message['replyTo'] != null &&
        message['replyTo']['type'] == 'product';
      
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                // Handle click on product reply
                if (replyingToProduct) {
                  final productId = message['replyTo']['id'];
                  _navigateToProduct(productId);
                }
              },
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighlighted
                    ? (isMe ? Colors.blue.shade300 : Colors.grey.shade400)
                    : (isMe ? Colors.blue.shade100 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Message replies
                    if (message['replyTo'] != null)
                      _buildReplyPreview(message),
                    
                    // Message text
                    Text(message['text'] ?? ''),
                    
                    const SizedBox(height: 4),
                    
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          messageTime,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                        ],
                        if (isFailed) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.error_outline, size: 12, color: Colors.red),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Only show retry button if message failed
            if (isFailed && isMe)
              TextButton.icon(
                onPressed: () => _retryFailedMessage(message),
                icon: Icon(Icons.refresh, size: 14),
                label: Text('Retry', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size(0, 24),
                ),
              ),
          ],
        ),
      );
    } catch (e) {
      print('Error building message item: $e');
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Text('Error displaying message', style: TextStyle(color: Colors.red)),
      );
    }
  }

  // Build reply preview inside a message
  Widget _buildReplyPreview(dynamic message) {
    try {
      final replyTo = message['replyTo'];
      if (replyTo == null) return SizedBox.shrink();
      
      // Handle product replies
      if (replyTo['type'] == 'product') {
        final productId = replyTo['id'];
        
        // Get a reference to the Future only once per productId to prevent rebuilds
        final Future<Map<String, dynamic>> productFuture = _fetchProductDetails(productId);
        
        return FutureBuilder<Map<String, dynamic>>(
          future: productFuture,
          builder: (context, snapshot) {
            // If we have data, immediately show it
            if (snapshot.hasData) {
              return _buildProductPreviewContent(snapshot.data!);
            }
            
            // If there's an error, show error state
            if (snapshot.hasError) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(6),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: Colors.red.shade300,
                      width: 4,
                    ),
                  ),
                ),
                child: Text(
                  'Product unavailable',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              );
            }
            
            // If still loading, show a stable loading state
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: Colors.green.shade700,
                    width: 4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shopping_bag, size: 12, color: Colors.green.shade700),
                  SizedBox(width: 4),
                  Text(
                    'Product',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Expanded(child: SizedBox()), // Spacer
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade700),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }
      
      // Handle message replies
      final replyToId = replyTo['id'];
      final originalMessage = messages.firstWhere(
        (m) => m['messageId'] != null && m['messageId'].toString() == replyToId.toString(),
        orElse: () => {'text': 'Original message not found', 'sender': currentUserId},
      );
      
      final messageText = originalMessage['text'] ?? 'Message unavailable';
      bool isOriginalSenderMe = false;
      
      if (originalMessage['sender'] != null) {
        if (originalMessage['sender'] is String) {
          isOriginalSenderMe = originalMessage['sender'].toString() == currentUserId.toString();
        } else if (originalMessage['sender'] is Map && originalMessage['sender']['_id'] != null) {
          isOriginalSenderMe = originalMessage['sender']['_id'].toString() == currentUserId.toString();
        }
      }
      
      return GestureDetector(
        onTap: () {
          _scrollToMessage(replyToId.toString());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(6),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: Colors.blue.shade700,
                width: 4,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isOriginalSenderMe ? 'You' : widget.partnerNames,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                messageText,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error building reply preview: $e');
      return Container(
        padding: const EdgeInsets.all(6),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Original message not available',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      );
    }
  }

  // Helper widget for product preview content
  Widget _buildProductPreviewContent(Map<String, dynamic> product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: Colors.green.shade700,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag, size: 12, color: Colors.green.shade700),
              SizedBox(width: 4),
              Text(
                'Product',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (product['imageUrl'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    base64Decode(product['imageUrl']),
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                  ),
                ),
              SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Product',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '₹${product['price'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(String text) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue.shade800,
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldShowDateHeader(int adjustedIndex) {
    if (adjustedIndex == 0) return true;
    
    if (adjustedIndex > 0 && adjustedIndex < filteredMessages.length) {
      final currentDate = DateTime.parse(filteredMessages[adjustedIndex]['createdAt']);
      final prevDate = DateTime.parse(filteredMessages[adjustedIndex - 1]['createdAt']);
      
      return currentDate.year != prevDate.year ||
        currentDate.month != prevDate.month ||
        currentDate.day != prevDate.day;
    }
    
    return false;
  }
}
