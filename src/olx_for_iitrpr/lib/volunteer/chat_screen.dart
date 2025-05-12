import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'view_profile.dart';
import 'server.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String partnerNames;
  final String partnerId;
  final Map? initialDonation;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.partnerNames,
    required this.partnerId,
    this.initialDonation,
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
  List<dynamic> filteredMessages = [];
  Set<String> processedMessageIds = {};
  bool isLoading = true;
  bool isBlocked = false;
  bool isCheckedBlocked = false;
  bool isSearching = false;
  bool showScrollToBottom = false;
  bool _initialLoadComplete = false;
  String currentUserId = '';
  String currentUserName = '';
  Timer? _refreshTimer;
  Uint8List? partnerProfilePicture;

  bool _isSending = false; // Add message debouncer flag
  final Map<String, dynamic> _messageMap = {}; // Add message map for deduplication

  @override
  void initState() {
    super.initState();

    _loadUserInfo();
    _loadLocalBlockStatus();
    _loadLocalMessages();
    _checkIfBlocked();
    _loadPartnerProfilePicture();

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_initialLoadComplete) {
          _fetchNewMessages();
        }
        _checkIfBlocked();
      },
    );

    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    _messageInputFocusNode.dispose();
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

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

  Future<void> _loadPartnerProfilePicture() async {
    try {
      final cachedPicture = await _secureStorage.read(key: 'profile_pic_${widget.partnerId}');
      if (cachedPicture != null) {
        if (mounted) {
          setState(() {
            partnerProfilePicture = base64Decode(cachedPicture);
          });
        }
        return;
      }

      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/profile-picture/${widget.partnerId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        if (response.headers['content-type']?.contains('application/json') != true) {
          if (mounted) {
            setState(() {
              partnerProfilePicture = response.bodyBytes;
            });

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

  void _navigateToUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewProfileScreen(userId: widget.partnerId),
      ),
    );
  }

  void _handleScroll() {
    if (_scrollController.hasClients) {
      setState(() {
        showScrollToBottom = _scrollController.position.pixels > 300;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

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
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

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

  Future<void> _saveBlockStatus(bool blocked) async {
    try {
      await _secureStorage.write(
        key: 'blocked_${widget.partnerId}',
        value: blocked ? 'true' : 'false',
      );
    } catch (e) {
      print('Error saving block status: $e');
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      String? id = await _secureStorage.read(key: 'userId');
      final name = await _secureStorage.read(key: 'userName');

      if (id == null || id.isEmpty) {
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
        Uri.parse('$serverUrl/api/users/blocked'),
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

        Set<String> localProcessedIds = {};
        for (var msg in loadedMessages) {
          if (msg['_id'] != null) {
            localProcessedIds.add(msg['_id'].toString());
            _messageMap[msg['_id'].toString()] = msg;
          }
        }

        setState(() {
          messages = _messageMap.values.toList();
          messages.sort((a, b) {
            final aTime = DateTime.parse(a['createdAt']);
            final bTime = DateTime.parse(b['createdAt']);
            return aTime.compareTo(bTime);
          });
          filteredMessages = messages;
          processedMessageIds = localProcessedIds;
          if (isLoading && messages.isNotEmpty) {
            isLoading = false;
          }
        });

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

  Future<void> _retryFailedMessage(dynamic message) async {
    if (message == null || message['text'] == null) return;

    final messageText = message['text'];
    final tempId = message['_id'].toString();

    setState(() {
      _messageMap.remove(tempId);
      messages = _messageMap.values.toList();
      if (!isSearching) {
        filteredMessages = messages;
      }
    });

    await _saveMessagesLocally();
    _messageController.text = messageText;
    await _sendMessage();
  }

  Future<void> _fetchMessages() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/conversations/${widget.conversationId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['conversation'] != null) {
          final serverMessages = data['conversation']['messages'] ?? [];

          for (var serverMsg in serverMessages) {
            if (serverMsg['_id'] != null) {
              String serverId = serverMsg['_id'].toString();
              _messageMap[serverId] = serverMsg;
              processedMessageIds.add(serverId);
            }
          }

          List<dynamic> combinedMessages = _messageMap.values.toList();
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

  Future<void> _fetchNewMessages() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      String url = '$serverUrl/api/conversations/${widget.conversationId}/messages';

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
          final serverMessages = data['messages'] ?? [];

          if (serverMessages.isNotEmpty) {
            bool hasNewMessages = false;

            for (var msg in serverMessages) {
              if (msg['_id'] != null) {
                final msgId = msg['_id'].toString();

                if (!_messageMap.containsKey(msgId)) {
                  _messageMap[msgId] = msg;
                  processedMessageIds.add(msgId);
                  hasNewMessages = true;
                }
              }
            }

            if (hasNewMessages) {
              setState(() {
                messages = _messageMap.values.toList();
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

              await _saveMessagesLocally();
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching new messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) {
      return;
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();
    _isSending = true;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimisticMessage = {
      '_id': tempId,
      'sender': {
        '_id': currentUserId,
        'name': currentUserName
      },
      'text': messageText,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'sending'
    };

    try {
      setState(() {
        _messageMap[tempId] = optimisticMessage;
        messages = _messageMap.values.toList();
        messages.sort((a, b) {
          final aTime = DateTime.parse(a['createdAt']);
          final bTime = DateTime.parse(b['createdAt']);
          return aTime.compareTo(bTime);
        });
        if (!isSearching) {
          filteredMessages = messages;
        }
      });

      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'text': messageText,
          'tempId': tempId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final serverMessage = data['message'];
          if (serverMessage != null) {
            setState(() {
              _messageMap.remove(tempId);

              if (serverMessage['sender'] == null) {
                serverMessage['sender'] = {
                  '_id': currentUserId,
                  'name': currentUserName
                };
              }

              _messageMap[serverMessage['_id'].toString()] = serverMessage;
              processedMessageIds.add(serverMessage['_id'].toString());

              messages = _messageMap.values.toList();
              messages.sort((a, b) {
                final aTime = DateTime.parse(a['createdAt']);
                final bTime = DateTime.parse(b['createdAt']);
                return aTime.compareTo(bTime);
              });
              if (!isSearching) {
                filteredMessages = messages;
              }
            });
            await _saveMessagesLocally();
          }
        } else {
          throw Exception('Failed to send message');
        }
      } else {
        throw Exception('Network error');
      }
    } catch (e) {
      print('Error sending message: $e');
      if (_messageMap.containsKey(tempId)) {
        setState(() {
          _messageMap[tempId]['status'] = 'failed';
        });
      }
    } finally {
      _isSending = false;
    }
  }

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
    ) ??
        false;

    if (!confirmed) return;

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/users/block/${widget.partnerId}'),
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
    ) ??
        false;

    if (!confirmed) return;

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.delete(
        Uri.parse('$serverUrl/api/users/unblock/${widget.partnerId}'),
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

  void _reportUser() {
    String reason = 'other';
    String details = '';
    bool includeChat = false;

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
                    Column(
                      children: reasonOptions
                          .map((option) => RadioListTile<String>(
                                title: Text(option['label']!),
                                value: option['value']!,
                                groupValue: reason,
                                onChanged: (value) {
                                  setState(() {
                                    reason = value!;
                                  });
                                },
                              ))
                          .toList(),
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
                      maxLength: 500,
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
                          child: Text(
                              'Share chat history with admin (helps with investigation)'),
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
          },
        );
      },
    );
  }

  Future<void> _submitReport(
      String reason, String details, bool includeChat) async {
    if (details.trim().isEmpty && reason == 'other') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please provide details for your report')),
      );
      return;
    }

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/users/report-user'),
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
            content: Text(
                'User reported successfully. Our team will review your report.'),
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

  PreferredSizeWidget _buildRegularAppBar() {
    return AppBar(
      backgroundColor: Colors.green.shade50,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      automaticallyImplyLeading: false,
      leadingWidth: 40,
      scrolledUnderElevation: 0,
      leading: Container(
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      title: InkWell(
        onTap: _navigateToUserProfile,
        child: Row(
          children: [
            Stack(
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
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.partnerNames,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Volunteer',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
                      isBlocked
                          ? Icons.lock_open
                          : Icons.block,
                      size: 18),
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
    );
  }

  Widget _buildMessageItem(dynamic message, bool isMe) {
    try {
      final DateTime utcTime = DateTime.parse(message['createdAt']);
      final DateTime localTime = utcTime.toLocal();
      final messageTime = DateFormat('HH:mm').format(localTime);

      final bool isPending = message['status'] == 'sending';
      final bool isFailed = message['status'] == 'failed';

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text(
                  widget.partnerNames,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
      return Container();
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
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade200,
                  ),
                  onChanged: _filterMessages,
                ),
              ),
            )
          : _buildRegularAppBar(),
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
                            final int adjustedIndex =
                                filteredMessages.length - 1 - index;
                            if (adjustedIndex < 0 ||
                                adjustedIndex >= filteredMessages.length) {
                              throw RangeError('Index out of range');
                            }

                            final message =
                                filteredMessages[adjustedIndex];

                            bool showDateHeader = false;
                            String dateHeaderText = '';

                            if (adjustedIndex == 0) {
                              showDateHeader = true;
                              final messageDate =
                                  DateTime.parse(message['createdAt']);
                              dateHeaderText =
                                  _formatDateForHeader(messageDate);
                            } else if (adjustedIndex > 0) {
                              final currentDate =
                                  DateTime.parse(message['createdAt']);
                              final prevMessage =
                                  filteredMessages[adjustedIndex - 1];
                              final prevDate =
                                  DateTime.parse(prevMessage['createdAt']);

                              if (currentDate.year != prevDate.year ||
                                  currentDate.month != prevDate.month ||
                                  currentDate.day != prevDate.day) {
                                showDateHeader = true;
                                dateHeaderText =
                                    _formatDateForHeader(currentDate);
                              }
                            }

                            bool isMe = false;
                            if (message['sender'] != null) {
                              if (message['sender'] is String) {
                                isMe = message['sender'].toString() ==
                                    currentUserId.toString();
                              } else if (message['sender'] is Map &&
                                  message['sender']['_id'] != null) {
                                isMe = message['sender']['_id']
                                        .toString() ==
                                    currentUserId.toString();
                              }
                            }

                            return Column(
                              children: [
                                if (showDateHeader)
                                  Container(
                                    margin: EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Center(
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                            vertical: 6,
                                            horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
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
                                _buildMessageItem(message, isMe),
                              ],
                            );
                          } catch (e) {
                            print(
                                'Error building message at index $index: $e');
                            return Container(height: 0);
                          }
                        },
                      ),
              ),
              if (isBlocked)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
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
                  padding: const EdgeInsets.only(
                      left: 8, right: 8, top: 0, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25.0),
                            color: const Color.fromARGB(
                                255, 255, 255, 255),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(
                                        255, 255, 255, 255)
                                    .withOpacity(0.2),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 0.0),
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageInputFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.only(
                                        left: 8,
                                        right: 8,
                                        top: 0,
                                        bottom: 0),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                              maxLines: null,
                            ),
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
                          icon: const Icon(Icons.send,
                              color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
}
