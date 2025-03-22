import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

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
  final FocusNode _messageInputFocusNode = FocusNode();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> messages = [];
  bool isLoading = true;
  bool isBlocked = false;
  String currentUserId = '';
  String currentUserName = '';
  Timer? _refreshTimer;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _swipingMessageId;
  double _messageSwipeOffset = 0.0;
  final double _replyThreshold = 60.0; // Distance needed to trigger reply
  AnimationController? _swipeController;
  Animation<double>? _swipeAnimation;

  // For reply functionality
  Map<String, dynamic>? _replyingTo;

  @override
  void initState() {
    super.initState();
    // Initialize the animation controller
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadUserInfo().then((_) {
      _loadLocalMessages();
      _fetchMessages();
      _checkIfBlocked();
    });
    
    // Set up periodic refresh
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _fetchMessages();
        _checkIfBlocked(); // Periodically check block status
      },
    );
  }

  @override
  void dispose() {
    _swipeController?.dispose();
    _messageController.dispose();
    _messageInputFocusNode.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
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
      // First try to get from local storage
      String? id = await _secureStorage.read(key: 'userId');
      final name = await _secureStorage.read(key: 'userName');
      
      // If userId is not in local storage, fetch from server
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
            // Save the fetched ID to local storage
            await _secureStorage.write(key: 'userId', value: id);
          }
        }
      }

      // Update state with the obtained values
      if (mounted) {
        setState(() {
          if (id != null) currentUserId = id;
          if (name != null) currentUserName = name;
        });
      }
    } catch (e) {
      print('Error loading user info: $e');
      // Handle error appropriately
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
        
        setState(() {
          isBlocked = blockedUsers.any((user) => 
            user['blocked'] != null && 
            (user['blocked'] is String ? 
              user['blocked'] == widget.partnerId : 
              user['blocked']['_id'] == widget.partnerId)
          );
        });
        
        // If block status changed, refresh messages
        if (wasBlocked != isBlocked) {
          _fetchMessages();
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
        setState(() {
          messages = json.decode(messagesJson);
          if (isLoading && messages.isNotEmpty) {
            isLoading = false;
          }
        });
        
        // Scroll to bottom after loading messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      print('Error loading local messages: $e');
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

  // Add this method to get or create a key for each message
  GlobalKey _getKeyForMessage(String messageId) {
    if (!_messageKeys.containsKey(messageId)) {
      _messageKeys[messageId] = GlobalKey();
    }
    return _messageKeys[messageId]!;
  }

  void _scrollToMessage(String messageId) {
    try {
      // Set the highlighted message
      setState(() {
        _highlightedMessageId = messageId;
      });
      
      // Find the index of the message to scroll to
      final messageIndex = messages.indexWhere((m) => 
        m['_id'] != null && m['_id'].toString() == messageId);
      
      if (messageIndex != -1) {
        // Calculate position in the reversed list
        final scrollIndex = messages.length - 1 - messageIndex;
        
        // Scroll to the position
        _scrollController.animateTo(
          scrollIndex * 75.0, // Approximate height of each message item
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        
        // As backup, try to use ensureVisible after a short delay to ensure rendering
        Future.delayed(const Duration(milliseconds: 200), () {
          final key = _getKeyForMessage(messageId);
          if (key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 300),
              alignment: 0.5, // Center it in viewport
            );
          }
        });
      }
      
      // Remove highlight after a delay
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
        if (data['success']) {
          // Get server messages
          final serverMessages = data['conversation']['messages'];
          
          // Extract pending messages
          final pendingMessages = messages.where((m) => m['status'] == 'pending').toList();
          
          // Get the IDs of pending messages
          final pendingIds = pendingMessages.map((m) => m['_id']).toSet();
          
          // Filter out server messages that match our pending messages
          // (to avoid duplicates when we add pending messages back)
          final filteredServerMessages = serverMessages.where((m) {
            // Keep only messages that aren't in our pending list
            return !pendingIds.contains(m['_id']);
          }).toList();
          
          setState(() {
            // Replace messages with filtered server messages plus pending ones
            messages = [...filteredServerMessages, ...pendingMessages];
            isLoading = false;
          });
          
          // Save messages to local storage
          _saveMessagesLocally();
        }
      }
    } catch (e) {
      print('Error fetching messages: $e');
      if (messages.isEmpty) {
        _loadLocalMessages();
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;
    
    // Clear input field immediately
    _messageController.clear();
    
    // Create a temporary ID for the pending message
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Create the pending message with clock status
    final pendingMessage = {
      '_id': tempId,
      'sender': currentUserId, // Just use the ID directly
      'text': messageText,
      'createdAt': DateTime.now().toIso8601String(),
      'replyToMessageId': _replyingTo?['id'],
      'status': 'pending'
    };
    
    // Add pending message to the list and clear reply state
    final _oldreplyingTo = _replyingTo;
    setState(() {
      messages = [...messages, pendingMessage]; // Keep at end for correct order
      _replyingTo = null;
    });
    
    // Force scroll to show the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    
    // Save updated messages to local storage
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
          'tempId': tempId, // Send tempId to server
        }),
      );
      
      if (response.statusCode == 200) {
        // Message was successfully sent
        final data = json.decode(response.body);
        if (data['success']) {
          // Check if the response includes the serverMessage and tempId
          if (data['tempId'] != null && data['serverMessage'] != null) {
            final receivedTempId = data['tempId'];
            final serverMessage = data['serverMessage'];
            
            // Update our local message by replacing the pending one
            setState(() {
              final index = messages.indexWhere((m) => 
                m['_id'].toString() == receivedTempId.toString());
              if (index != -1) {
                messages[index] = serverMessage;
              }
            });
            
            // Save the updated messages
            _saveMessagesLocally();
          }
        }
      } else {
        // Server error, mark message as failed
        setState(() {
          final index = messages.indexWhere((m) => 
            m['_id'] != null && m['_id'].toString() == tempId.toString());
          if (index != -1) {
            messages[index]['status'] = 'failed';
          }
        });
        
        _saveMessagesLocally();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message. Please try again.')),
        );
      }
    } catch (e) {
      // Network error, mark message as failed
      setState(() {
        final index = messages.indexWhere((m) => 
          m['_id'] != null && m['_id'].toString() == tempId.toString());
        if (index != -1) {
          messages[index]['status'] = 'failed';
        }
      });
      
      _saveMessagesLocally();
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  void _handleReply(dynamic message) {
    setState(() {
      _replyingTo = {
        'id': message['_id'],
        'text': message['text'],
      };
    });
    // Focus the text input
    FocusScope.of(context).requestFocus(_messageInputFocusNode);
  }

  void _showSearchDialog() {
    String searchQuery = '';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Search Messages'),
          content: TextField(
            onChanged: (value) {
              searchQuery = value;
            },
            decoration: InputDecoration(hintText: "Enter search term"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Search'),
              onPressed: () {
                Navigator.of(context).pop();
                _performSearch(searchQuery);
              },
            ),
          ],
        );
      },
    );
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      _fetchMessages();
      return;
    }
    
    List<dynamic> filteredMessages = messages.where((message) =>
      message['text'].toString().toLowerCase().contains(query.toLowerCase())
    ).toList();
    
    setState(() {
      messages = filteredMessages;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Found ${filteredMessages.length} messages'),
        action: SnackBarAction(
          label: 'Clear',
          onPressed: () {
            _fetchMessages();
          },
        ),
      )
    );
  }

  Future<void> _blockUser() async {
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

  void _reportUser() {
    bool includeChat = false;
    String reason = '';
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Report User'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (value) {
                      reason = value;
                    },
                    decoration: InputDecoration(
                      hintText: "Enter reason for reporting"
                    ),
                    maxLines: 3,
                  ),
                  SizedBox(height: 16),
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
                        child: Text('Share chat history with admin'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text('Report'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _submitReport(reason, includeChat);
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _submitReport(String reason, bool includeChat) async {
    if (reason.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please provide a reason for reporting')),
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
          'includeChat': includeChat,
          'conversationId': includeChat ? widget.conversationId : null,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User reported successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to report user')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.partnerNames),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'search':
                  _showSearchDialog();
                  break;
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
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'search',
                child: Text('Search'),
              ),
              PopupMenuItem<String>(
                value: 'block',
                child: Text(isBlocked ? 'Unblock User' : 'Block User'),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Text('Report User'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      try {
                        // Ensure we're working with integers
                        final int adjustedIndex = messages.length - 1 - index;
                        // Boundary check
                        if (adjustedIndex < 0 || adjustedIndex >= messages.length) {
                          throw RangeError('Index out of range');
                        }
                        final message = messages[adjustedIndex];
                        final messageId = message['_id'].toString();
                        
                        // Modified isMe check to handle both formats
                        bool isMe = false;
                        if (message['sender'] != null) {
                          // Handle non-populated format (string)
                          if (message['sender'] is String) {
                            isMe = message['sender'].toString() == currentUserId.toString();
                          } 
                          // Handle populated format (object with _id)
                          else if (message['sender'] is Map && message['sender']['_id'] != null) {
                            isMe = message['sender']['_id'].toString() == currentUserId.toString();
                          }
                        }
                        
                        // Calculate offset for this specific message
                        double offset = _swipingMessageId == messageId ? _messageSwipeOffset : 0.0;
                        
                        return GestureDetector(
                          key: _getKeyForMessage(messageId),
                          onHorizontalDragStart: (details) {
                            // Only allow right swipe (from left to right)
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
                                // Allow both positive and negative movement
                                _messageSwipeOffset = _messageSwipeOffset + details.delta.dx;
                                
                                // Prevent from going too far in either direction
                                if (_messageSwipeOffset > 100) {
                                  _messageSwipeOffset = 100;
                                } else if (_messageSwipeOffset < 0) {
                                  _messageSwipeOffset = 0; // Don't allow negative values
                                }
                              });
                            }
                          },
                          onHorizontalDragEnd: (details) {
                            if (_swipingMessageId == messageId) {
                              if (_messageSwipeOffset >= _replyThreshold) {
                                // Threshold reached, trigger reply
                                _handleReply(message);
                              }
                              
                              // Reset swipe state with animation
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
                                // Optional: Add reply icon that becomes visible during swipe
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
                        );
                      } catch (e) {
                        print('Error building message at index $index: $e');
                        return Container(height: 0);
                      }
                    },
                  ),
          ),
          
          // Show Unblock button if user is blocked, otherwise show message input
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
                  // Message input with integrated reply
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25.0),
                        color: const Color.fromARGB(255, 255, 255, 255), // Main container background
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
                          // Reply UI with properly colored sections
                          if (_replyingTo != null)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(25.0),
                                  topRight: Radius.circular(25.0),
                                ),
                                color: Colors.white, // White background for the entire container
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Grey section containing username and reply text
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
                                  // Small white space to make the transition look better
                                ],
                              ),
                            ),
                          // Text input field with white background
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
                                fillColor: Colors.white,  // Set background color to white
                              ),
                              onSubmitted: (_) => _sendMessage(),
                              maxLines: null, // Allow multiple lines
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Separate send button with space between
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
    );
  }

  // Helper method to determine sender name for reply
  String _getSenderNameForReply() {
    try {
      // Find the original message
      final replyIdString = _replyingTo!['id'].toString();
      final originalMessage = messages.firstWhere(
        (m) => m['_id'] != null && m['_id'].toString() == replyIdString,
        orElse: () => {'sender': null},
      );
      
      // Determine if the original sender was the current user
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

  // Update _buildMessageItem to highlight messages
  Widget _buildMessageItem(dynamic message, bool isMe) {
    try {
      final messageTime = DateFormat('HH:mm').format(
        DateTime.parse(message['createdAt']),
      );
      
      final bool isPending = message['status'] == 'pending';
      final bool isHighlighted = message['_id'] != null && 
                                message['_id'].toString() == _highlightedMessageId;
      
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // Change background color when highlighted
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
                  ]
                ],
              ),
            ],
          ),
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
      
      // Determine if original sender was current user
      bool isOriginalSenderMe = false;
      if (originalMessage['sender'] != null) {
        if (originalMessage['sender'] is String) {
          isOriginalSenderMe = originalMessage['sender'].toString() == currentUserId.toString();
        } else if (originalMessage['sender'] is Map && originalMessage['sender']['_id'] != null) {
          isOriginalSenderMe = originalMessage['sender']['_id'].toString() == currentUserId.toString();
        }
      }
      
      final isCurrentSenderMe = message['sender'].toString() == currentUserId.toString();
      
      // Add GestureDetector to make it tappable
      return GestureDetector(
        onTap: () {
          // Scroll to original message when tapped
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
