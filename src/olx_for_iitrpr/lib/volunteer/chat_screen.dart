import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'view_profile.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String partnerNames;
  final String partnerId;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.partnerNames,
    required this.partnerId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _messageInputFocusNode = FocusNode();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> messages = [];
  List<dynamic> filteredMessages = []; // For search results
  Set<String> processedMessageIds = {}; // Track processed message IDs to prevent duplicates
  bool isLoading = true;
  bool isBlocked = false;
  bool isCheckedBlocked = false;
  bool isSearching = false;
  bool showScrollToBottom = false; // State for scroll-to-bottom button
  bool _initialLoadComplete = false; // Track if initial load is complete
  String currentUserId = '';
  String currentUserName = '';
  Timer? _refreshTimer;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _swipingMessageId;
  double _messageSwipeOffset = 0.0;
  final double _replyThreshold = 60.0;
  AnimationController? _swipeController;
  Animation<double>? _swipeAnimation;
  Uint8List? partnerProfilePicture;

  // For reply functionality
  Map<String, dynamic>? _replyingTo;

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _loadUserInfo();
    _loadLocalBlockStatus();
    _loadLocalMessages();
    _checkIfBlocked();
    _loadPartnerProfilePicture();
    
    // Set up periodic refresh
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_initialLoadComplete) {
          _fetchNewMessages();
        }
        _checkIfBlocked();
      },
    );
    
    // Add scroll listener for showing scroll-to-bottom button
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _swipeController?.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _messageInputFocusNode.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Get the latest message ID for incremental loading
  String? _getLatestMessageId() {
    if (messages.isEmpty) return null;
    
    DateTime latestTime = DateTime.parse(messages[0]['createdAt']);
    String latestId = messages[0]['_id'].toString();
    
    for (var message in messages) {
      final messageTime = DateTime.parse(message['createdAt']);
      if (messageTime.isAfter(latestTime)) {
        latestTime = messageTime;
        latestId = message['_id'].toString();
      }
    }
    
    return latestId;
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
            
            // Cache the profile picture
            await _secureStorage.write(
              key: 'profile_pic_${widget.partnerId}',
              value: base64Encode(response.bodyBytes),
            );
          }
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

  // Scroll listener for showing scroll-to-bottom button
  void _handleScroll() {
    if (_scrollController.hasClients) {
      setState(() {
        showScrollToBottom = _scrollController.position.pixels > 300;
      });
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
    }
  }

  // Format date for header display (Today, Yesterday, day of week, or date)
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

  void _resetSwipe() {
    if (_swipingMessageId != null) {
      _swipeController?.reverse().then((_) {
        setState(() {
          _swipingMessageId = null;
          _messageSwipeOffset = 0.0;
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
        final List<dynamic> blockedUsers = json.decode(response.body);
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

  Future<void> _loadLocalMessages() async {
    try {
      final messagesJson = await _secureStorage.read(key: 'messages_${widget.conversationId}');
      if (messagesJson != null) {
        final loadedMessages = json.decode(messagesJson);
        
        // Initialize the set of processed message IDs
        Set<String> localProcessedIds = {};
        for (var msg in loadedMessages) {
          if (msg['_id'] != null) {
            localProcessedIds.add(msg['_id'].toString());
          }
        }
        
        setState(() {
          messages = loadedMessages;
          filteredMessages = messages;
          processedMessageIds = localProcessedIds; // This initialization is crucial for deduplication
          if (isLoading && messages.isNotEmpty) {
            isLoading = false;
          }
        });
        
        // After loading local messages, fetch from server to get latest
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchMessages();
          _initialLoadComplete = true;
          
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
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

  Future<void> _saveMessagesLocally() async {
    try {
      await _secureStorage.write(
        key: 'messages_${widget.conversationId}',
        value: json.encode(messages),
      );
    } catch (e) {
      print('Error saving messages locally: $e');
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
        m['_id'] != null && m['_id'].toString() == messageId);
      
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
      }
      
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    } catch (e) {
      print('Error scrolling to message: $e');
    }
  }

  // Full fetch for initial load
  Future<void> _fetchMessages() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['conversation'] != null) {
          final serverMessages = data['conversation']['messages'] ?? [];
          
          // Create a map to efficiently track what we already have
          Map<String, dynamic> messageMap = {};
          
          // First, add existing local messages to the map
          for (var msg in messages) {
            if (msg['_id'] != null) {
              String id = msg['_id'].toString();
              messageMap[id] = msg;
              processedMessageIds.add(id);
            }
          }
          
          // Then add server messages, replacing duplicates
          for (var serverMsg in serverMessages) {
            if (serverMsg['_id'] != null) {
              String serverId = serverMsg['_id'].toString();
              
              // If this message exists locally and has a status, preserve the status
              if (messageMap.containsKey(serverId) && messageMap[serverId]['status'] != null) {
                serverMsg['status'] = messageMap[serverId]['status'];
              }
              
              messageMap[serverId] = serverMsg;
              processedMessageIds.add(serverId);
            }
          }
          
          // Convert map back to list and sort
          List<dynamic> combinedMessages = messageMap.values.toList();
          combinedMessages.sort((a, b) {
            final aTime = DateTime.parse(a['createdAt']);
            final bTime = DateTime.parse(b['createdAt']);
            return aTime.compareTo(bTime);
          });
          
          if (mounted) {
            setState(() {
              messages = combinedMessages;
              if (!isSearching) {
                filteredMessages = combinedMessages;
              } else {
                _filterMessages(_searchController.text);
              }
              isLoading = false;
            });
          }
          
          // Save the updated message list to local storage
          _saveMessagesLocally();
        }
      }
    } catch (e) {
      print('Error fetching messages: $e');
      if (messages.isEmpty) {
        _loadLocalMessages();
      }
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  // Incremental fetch for periodic updates
  Future<void> _fetchNewMessages() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      String url = 'https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages';
      
      // Add since parameter for incremental loading
      final latestMessageId = _getLatestMessageId();
      if (latestMessageId != null) {
        url += '?since=${latestMessageId}';
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
        if (data['success']) {
          // For incremental updates, we only get new messages
          final newMessages = data['messages'] ?? [];
          
          if (newMessages.isNotEmpty) {
            // Process new messages
            List<dynamic> messagesToAdd = [];
            
            // Only add new messages that haven't been processed yet
            for (var newMsg in newMessages) {
              if (newMsg['_id'] != null) {
                final msgId = newMsg['_id'].toString();
                if (!processedMessageIds.contains(msgId)) {
                  messagesToAdd.add(newMsg);
                  processedMessageIds.add(msgId);
                }
              }
            }
            
            if (messagesToAdd.isNotEmpty) {
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
              });
              
              // Save the updated message list
              await _saveMessagesLocally();
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching new messages: $e');
    }
  }

  Future<void> _retryFailedMessage(dynamic failedMessage) async {
    final failedMessageId = failedMessage['_id'].toString();
    final messageText = failedMessage['text'];
    final replyToMessageId = failedMessage['replyToMessageId'];
    
    // Update status to pending
    setState(() {
      final index = messages.indexWhere((m) => 
        m['_id'].toString() == failedMessageId);
      if (index != -1) {
        messages[index]['status'] = 'pending';
        
        // Also update in filtered messages if present
        final filteredIndex = filteredMessages.indexWhere((m) => 
          m['_id'].toString() == failedMessageId);
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
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'text': messageText,
          'replyToMessageId': replyToMessageId,
          'tempId': failedMessageId,
        }),
      );
      
      // Always mark as "sent" to hide if user is blocked
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => 
            m['_id'].toString() == failedMessageId);
          if (index != -1) {
            messages[index]['status'] = 'sent';
            
            // Also update in filtered messages if present
            final filteredIndex = filteredMessages.indexWhere((m) => 
              m['_id'].toString() == failedMessageId);
            if (filteredIndex != -1) {
              filteredMessages[filteredIndex]['status'] = 'sent';
            }
          }
        });
        
        _saveMessagesLocally();
      }
    } catch (e) {
      // Even for errors, mark as sent to hide blocking
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => 
            m['_id'].toString() == failedMessageId);
          if (index != -1) {
            messages[index]['status'] = 'sent';
            
            // Also update in filtered messages if present
            final filteredIndex = filteredMessages.indexWhere((m) => 
              m['_id'].toString() == failedMessageId);
            if (filteredIndex != -1) {
              filteredMessages[filteredIndex]['status'] = 'sent';
            }
          }
        });
      }
      
      _saveMessagesLocally();
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;
    
    _messageController.clear();
    
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final pendingMessage = {
      '_id': tempId,
      'sender': currentUserId,
      'text': messageText,
      'createdAt': DateTime.now().toIso8601String(),
      'replyToMessageId': _replyingTo?['id'],
      'status': 'pending'
    };
    
    // Add to processedMessageIds to prevent duplicates
    processedMessageIds.add(tempId);
    
    final _oldreplyingTo = _replyingTo;
    setState(() {
      messages = [...messages, pendingMessage];
      if (!isSearching) {
        filteredMessages = messages;
      } else {
        _filterMessages(_searchController.text);
      }
      _replyingTo = null;
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    
    // Save to local storage immediately (even if blocked)
    await _saveMessagesLocally();
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'text': messageText,
          'replyToMessageId': _oldreplyingTo?['id'],
          'tempId': tempId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // If server returned a message ID, add it to processed IDs to prevent duplication
          if (data['serverMessage'] != null && data['serverMessage']['_id'] != null) {
            processedMessageIds.add(data['serverMessage']['_id'].toString());
          }
          
          if (mounted) {
            setState(() {
              final index = messages.indexWhere((m) => 
                m['_id'].toString() == tempId);
              if (index != -1) {
                messages[index]['status'] = 'sent';
                
                // Update in filtered messages if present
                final filteredIndex = filteredMessages.indexWhere((m) => 
                  m['_id'].toString() == tempId);
                if (filteredIndex != -1) {
                  filteredMessages[filteredIndex]['status'] = 'sent';
                }
              }
            });
          }
          
          _saveMessagesLocally();
        }
      } else {
        // Mark as sent anyway (to handle blocked scenario)
        if (mounted) {
          setState(() {
            final index = messages.indexWhere((m) => 
              m['_id'].toString() == tempId);
            if (index != -1) {
              messages[index]['status'] = 'sent';
              
              // Update in filtered messages if present
              final filteredIndex = filteredMessages.indexWhere((m) => 
                m['_id'].toString() == tempId);
              if (filteredIndex != -1) {
                filteredMessages[filteredIndex]['status'] = 'sent';
              }
            }
          });
        }
        
        _saveMessagesLocally();
      }
    } catch (e) {
      // Mark as sent even on error (to hide blocking)
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => 
            m['_id'].toString() == tempId);
          if (index != -1) {
            messages[index]['status'] = 'sent';
            
            // Update in filtered messages if present
            final filteredIndex = filteredMessages.indexWhere((m) => 
              m['_id'].toString() == tempId);
            if (filteredIndex != -1) {
              filteredMessages[filteredIndex]['status'] = 'sent';
            }
          }
        });
      }
      
      _saveMessagesLocally();
      print('Error sending message: $e');
    }
  }

  void _handleReply(dynamic message) {
    setState(() {
      _replyingTo = {
        'id': message['_id'],
        'text': message['text'],
      };
    });
    FocusScope.of(context).requestFocus(_messageInputFocusNode);
  }

  // New method for filtering messages
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

  Future<void> _blockUser() async {
    bool confirmed = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Block User'),
          content: Text('Are you sure you want to block ${widget.partnerNames}?'),
          actions: <Widget>[
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

  Future<void> _unblockUser() async {
    bool confirmed = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Unblock User'),
          content: Text('Are you sure you want to unblock ${widget.partnerNames}?'),
          actions: <Widget>[
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

  // Enhanced reporting function matching the server schema
  void _reportUser() {
    String reason = 'other'; // Default reason
    String details = '';
    bool includeChat = false;
    
    // Define reason options based on the server schema
    final List<Map<String, String>> reasonOptions = [
      {'value': 'spam', 'label': 'Spam'},
      {'value': 'harassment', 'label': 'Harassment'},
      {'value': 'inappropriate_content', 'label': 'Inappropriate Content'},
      {'value': 'fake_account', 'label': 'Fake Account'},
      {'value': 'other', 'label': 'Other'}
    ];
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Report User'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reason for reporting:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // Reason selection
                    Column(
                      children: reasonOptions.map((option) => 
                        RadioListTile<String>(
                          title: Text(option['label']!),
                          value: option['value']!,
                          groupValue: reason,
                          onChanged: (value) {
                            setState(() {
                              reason = value!;
                            });
                          },
                        )
                      ).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Additional details:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (value) {
                        details = value;
                      },
                      decoration: InputDecoration(
                        hintText: "Please provide more information",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                      maxLength: 500, // Match schema maxlength
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: includeChat,
                          onChanged: (value) {
                            setState(() {
                              includeChat = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text('Share chat history with admin (helps with investigation)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                  ),
                  child: Text('Report'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _submitReport(reason, details, includeChat);
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _submitReport(String reason, String details, bool includeChat) async {
    if (details.trim().isEmpty && reason == 'other') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please provide details for your report')),
      );
      return;
    }
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/report-user'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'reportedUserId': widget.partnerId,
          'reason': reason,
          'details': details,
          'includeChat': includeChat,
          'conversationId': includeChat ? widget.conversationId : null,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User reported successfully. Our team will review your report.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to report user. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isCheckedBlocked && isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.partnerNames),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: isSearching
          ? AppBar(
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
            )
          : AppBar(
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
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'block':
                        if (isBlocked) {
                          _unblockUser();
                        } else {
                          _blockUser();
                        }
                        break;
                      case 'report':
                        _reportUser();
                        break;
                      case 'view_profile':
                        _navigateToUserProfile();
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'view_profile',
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 18),
                          SizedBox(width: 8),
                          Text('View Profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
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
                    const PopupMenuItem<String>(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag, size: 18),
                          SizedBox(width: 8),
                          Text('Report User'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: filteredMessages.length,
                        itemBuilder: (context, index) {
                          try {
                            final int adjustedIndex = filteredMessages.length - 1 - index;
                            if (adjustedIndex < 0 || adjustedIndex >= filteredMessages.length) {
                              throw RangeError('Index out of range');
                            }
                            
                            final message = filteredMessages[adjustedIndex];
                            final messageId = message['_id'].toString();
                            
                            // Check if we need to show a date header
                            bool showDateHeader = false;
                            String dateHeaderText = '';
                            
                            if (adjustedIndex == 0) {
                              // Always show date header for the first message
                              showDateHeader = true;
                              final messageDate = DateTime.parse(message['createdAt']);
                              dateHeaderText = _formatDateForHeader(messageDate);
                            } else if (adjustedIndex > 0) {
                              // Compare with previous message date
                              final currentDate = DateTime.parse(message['createdAt']);
                              final prevMessage = filteredMessages[adjustedIndex - 1];
                              final prevDate = DateTime.parse(prevMessage['createdAt']);
                              
                              // If dates are different, show header
                              if (currentDate.year != prevDate.year ||
                                  currentDate.month != prevDate.month ||
                                  currentDate.day != prevDate.day) {
                                showDateHeader = true;
                                dateHeaderText = _formatDateForHeader(currentDate);
                              }
                            }
                            
                            bool isMe = false;
                            if (message['sender'] != null) {
                              if (message['sender'] is String) {
                                isMe = message['sender'].toString() == currentUserId.toString();
                              } 
                              else if (message['sender'] is Map && message['sender']['_id'] != null) {
                                isMe = message['sender']['_id'].toString() == currentUserId.toString();
                              }
                            }
                            
                            double offset = _swipingMessageId == messageId ? _messageSwipeOffset : 0.0;
                            
                            return Column(
                              children: [
                                if (showDateHeader)
                                  Container(
                                    margin: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05),
                                              blurRadius: 2,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          dateHeaderText,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                GestureDetector(
                                  key: _getKeyForMessage(messageId),
                                  onHorizontalDragStart: (details) {
                                    if (details.localPosition.dx < MediaQuery.of(context).size.width / 2) {
                                      setState(() {
                                        _swipingMessageId = messageId;
                                        _messageSwipeOffset = 0.0;
                                      });
                                    }
                                  },
                                  onHorizontalDragUpdate: (details) {
                                    if (_swipingMessageId == messageId) {
                                      setState(() {
                                        _messageSwipeOffset = _messageSwipeOffset + details.delta.dx;
                                        
                                        if (_messageSwipeOffset > 100) {
                                          _messageSwipeOffset = 100;
                                        } else if (_messageSwipeOffset < 0) {
                                          _messageSwipeOffset = 0;
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
                                  behavior: HitTestBehavior.translucent,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 50),
                                    transform: Matrix4.translationValues(offset, 0, 0),
                                    child: Row(
                                      children: [
                                        if (offset > 0)
                                          Container(
                                            width: 20,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.reply,
                                              size: 16,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        Expanded(
                                          child: _buildMessageItem(message, isMe),
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
                                                color: Colors.blue,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _getSenderNameForReply(),
                                                    style: TextStyle(
                                                      color: Colors.blue,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _replyingTo!['text'],
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
          // Scroll to bottom button
          if (showScrollToBottom)
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue.shade100,
                child: Icon(
                  Icons.arrow_downward,
                  color: Colors.blue.shade800,
                ),
                onPressed: _scrollToBottom,
              ),
            ),
        ],
      ),
    );
  }

  String _getSenderNameForReply() {
    try {
      final replyIdString = _replyingTo!['id'].toString();
      final originalMessage = messages.firstWhere(
        (m) => m['_id'] != null && m['_id'].toString() == replyIdString,
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

  Widget _buildMessageItem(dynamic message, bool isMe) {
    try {
      final messageTime = DateFormat('HH:mm').format(
        DateTime.parse(message['createdAt']),
      );
      
      final bool isPending = message['status'] == 'pending';
      final bool isFailed = message['status'] == 'failed';
      final bool isHighlighted = message['_id'] != null && 
                                message['_id'].toString() == _highlightedMessageId;
      
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
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
                  if (message['replyToMessageId'] != null)
                    _buildReplyPreview(message),
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

  Widget _buildReplyPreview(dynamic message) {
    try {
      final replyIdString = message['replyToMessageId'].toString();
      
      final originalMessage = messages.firstWhere(
        (m) => m['_id'] != null && m['_id'].toString() == replyIdString,
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
      
      final isCurrentSenderMe = message['sender'].toString() == currentUserId.toString();
      
      return GestureDetector(
        onTap: () {
          _scrollToMessage(replyIdString);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(6),
          width: double.infinity,
          decoration: BoxDecoration(
            color: isCurrentSenderMe ? Colors.blue.shade200 : Colors.grey.shade300,
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
}
