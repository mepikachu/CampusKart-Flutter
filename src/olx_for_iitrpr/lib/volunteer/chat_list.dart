import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> conversations = [];
  Map<String, Uint8List> profilePictures = {};
  Map<String, int> unreadMessageCounts = {};
  Map<String, String> lastReadMessageIds = {};
  bool isLoading = true;
  String errorMessage = '';
  String currentUserName = '';
  String currentUserId = '';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser().then((_) {
      _loadLastReadMessageIds();
      _loadLocalConversations();
      fetchConversations();
    });
    
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => fetchConversations(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Try to get from local storage first
      final id = await _secureStorage.read(key: 'userId');
      final name = await _secureStorage.read(key: 'userName');
      
      // If missing, fetch from server
      if (id == null || name == null) {
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
            await _secureStorage.write(key: 'userId', value: data['user']['_id']);
            await _secureStorage.write(key: 'userName', value: data['user']['userName']);
            setState(() {
              currentUserId = data['user']['_id'];
              currentUserName = data['user']['userName'];
            });
          }
        }
      } else {
        setState(() {
          currentUserId = id;
          currentUserName = name;
        });
      }
    } catch (e) {
      print('Error loading user: $e');
    }
  }

  Future<void> _loadLastReadMessageIds() async {
    try {
      final json = await _secureStorage.read(key: 'lastReadMessageIds');
      if (json != null) {
        setState(() {
          lastReadMessageIds = Map<String, String>.from(jsonDecode(json));
        });
      }
    } catch (e) {
      print('Error loading last read message IDs: $e');
    }
  }

  Future<void> _saveLastReadMessageIds() async {
    try {
      await _secureStorage.write(
        key: 'lastReadMessageIds',
        value: jsonEncode(lastReadMessageIds),
      );
    } catch (e) {
      print('Error saving last read message IDs: $e');
    }
  }

  Future<void> _loadLocalConversations() async {
    try {
      final conversationsJson = await _secureStorage.read(key: 'conversations');
      if (conversationsJson != null) {
        List<dynamic> localConversations = json.decode(conversationsJson);
        
        // Load local pending messages for each conversation
        for (var conversation in localConversations) {
          String conversationId = conversation['_id'];
          await _mergeLocalMessages(conversation);
        }
        
        // Sort by most recent message
        localConversations.sort((a, b) {
          final aTime = a['messages']?.isNotEmpty == true
              ? DateTime.parse(a['messages'].last['createdAt'])
              : DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b['messages']?.isNotEmpty == true
              ? DateTime.parse(b['messages'].last['createdAt'])
              : DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
        
        setState(() {
          conversations = localConversations;
          _updateUnreadCounts();
          if (isLoading && conversations.isNotEmpty) {
            isLoading = false;
          }
        });
        
        // Load profile pictures
        for (var conversation in conversations) {
          _loadProfilePicture(conversation);
        }
      }
    } catch (e) {
      print('Error loading local conversations: $e');
    }
  }

  Future<void> _mergeLocalMessages(dynamic conversation) async {
    try {
      final String conversationId = conversation['_id'];
      final localMessagesJson = await _secureStorage.read(key: 'messages_$conversationId');
      
      if (localMessagesJson != null) {
        final localMessages = json.decode(localMessagesJson);
        
        // Get pending/failed messages that are stored locally
        final pendingOrFailedMessages = localMessages.where((m) => 
          m['status'] == 'pending' || m['status'] == 'failed'
        ).toList();
        
        if (pendingOrFailedMessages.isNotEmpty) {
          // Add these messages to the conversation if they're not already there
          if (conversation['messages'] == null) {
            conversation['messages'] = [];
          }
          
          // Create a set of existing message IDs for quick lookup
          final existingIds = Set<String>.from(
            conversation['messages']
                .where((m) => m['_id'] != null)
                .map((m) => m['_id'].toString())
          );
          
          // Add pending/failed messages that aren't already in the conversation
          for (var message in pendingOrFailedMessages) {
            if (!existingIds.contains(message['_id'].toString())) {
              conversation['messages'].add(message);
            }
          }
          
          // Sort messages by creation time
          conversation['messages'].sort((a, b) {
            final aTime = DateTime.parse(a['createdAt']);
            final bTime = DateTime.parse(b['createdAt']);
            return aTime.compareTo(bTime);
          });
        }
      }
    } catch (e) {
      print('Error merging local messages: $e');
    }
  }

  Future<void> _saveConversationsLocally() async {
    try {
      await _secureStorage.write(
        key: 'conversations',
        value: json.encode(conversations),
      );
    } catch (e) {
      print('Error saving conversations locally: $e');
    }
  }

  void _updateUnreadCounts() {
    unreadMessageCounts = {};
    
    for (var conversation in conversations) {
      final conversationId = conversation['_id'];
      final lastReadId = lastReadMessageIds[conversationId];
      int unreadCount = 0;
      
      if (conversation['messages']?.isNotEmpty == true) {
        if (lastReadId == null) {
          // If no message has been read, all messages are unread
          // Only count messages from the other user as unread
          unreadCount = conversation['messages']
              .where((m) => 
                m['sender'] != null && 
                (m['sender'] is String 
                  ? m['sender'] != currentUserId
                  : m['sender']['_id'] != currentUserId))
              .length;
        } else {
          // Find the index of the last read message
          final lastReadIndex = conversation['messages']
              .indexWhere((m) => m['_id'].toString() == lastReadId);
          
          if (lastReadIndex == -1) {
            // Last read message not found, count all messages from other user
            unreadCount = conversation['messages']
                .where((m) => 
                  m['sender'] != null && 
                  (m['sender'] is String 
                    ? m['sender'] != currentUserId
                    : m['sender']['_id'] != currentUserId))
                .length;
          } else {
            // Count messages after the last read message from other user
            unreadCount = conversation['messages']
                .sublist(lastReadIndex + 1)
                .where((m) => 
                  m['sender'] != null && 
                  (m['sender'] is String 
                    ? m['sender'] != currentUserId
                    : m['sender']['_id'] != currentUserId))
                .length;
          }
        }
      }
      
      if (unreadCount > 0) {
        unreadMessageCounts[conversationId] = unreadCount;
      }
    }
  }

  Future<void> fetchConversations() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final serverConversations = data['conversations'];
          
          // Merge with local messages for each conversation
          for (var conversation in serverConversations) {
            await _mergeLocalMessages(conversation);
          }
          
          serverConversations.sort((a, b) {
            final aTime = a['messages']?.isNotEmpty == true
                ? DateTime.parse(a['messages'].last['createdAt'])
                : DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b['messages']?.isNotEmpty == true
                ? DateTime.parse(b['messages'].last['createdAt'])
                : DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
          
          if (mounted) {
            setState(() {
              conversations = serverConversations;
              _updateUnreadCounts();
              isLoading = false;
            });
          }
          
          // Load profile pictures
          for (var conversation in conversations) {
            _loadProfilePicture(conversation);
          }
          
          _saveConversationsLocally();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = e.toString());
      }
      if (conversations.isEmpty) _loadLocalConversations();
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadProfilePicture(dynamic conversation) async {
    try {
      if (conversation['participants']?.length >= 2) {
        final participants = conversation['participants'];
        // Get the partner (not current user)
        final partner = participants.firstWhere(
          (p) => p['_id'] != currentUserId,
          orElse: () => null,
        );
        
        if (partner != null) {
          final partnerId = partner['_id'];
          
          // Check if we already have this profile picture in memory
          if (profilePictures.containsKey(partnerId)) {
            return;
          }
          
          // Check if we have it cached locally
          final cachedPicture = await _secureStorage.read(key: 'profile_pic_$partnerId');
          if (cachedPicture != null) {
            if (mounted) {
              setState(() {
                profilePictures[partnerId] = base64Decode(cachedPicture);
              });
            }
            return;
          }
          
          // If not, fetch from server
          final authCookie = await _secureStorage.read(key: 'authCookie');
          final response = await http.get(
            Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/profile-picture/$partnerId'),
            headers: {
              'Content-Type': 'application/json',
              'auth-cookie': authCookie ?? '',
            },
          );
          
          if (response.statusCode == 200) {
            // Check if response is JSON (error) or binary (actual image)
            if (response.headers['content-type']?.contains('application/json') == true) {
              // This is JSON, likely an error or no image
              print('No profile picture available for user $partnerId');
              return;
            }
            
            // This is the binary image data
            if (mounted) {
              setState(() {
                profilePictures[partnerId] = response.bodyBytes;
              });
            }
            
            // Cache locally
            await _secureStorage.write(
              key: 'profile_pic_$partnerId',
              value: base64Encode(response.bodyBytes),
            );
          } else if (response.statusCode == 404) {
            // No profile picture, that's okay
            print('No profile picture found for user $partnerId');
          } else {
            print('Error fetching profile picture: ${response.statusCode}');
          }
        }
      }
    } catch (e) {
      print('Error loading profile picture: $e');
    }
  }

  String getPartnerName(dynamic conversation) {
    if (conversation['participants']?.length == 2) {
      final participants = conversation['participants'];
      // Compare by ID instead of username
      final isFirstParticipantMe = participants[0]['_id'] == currentUserId;
      return isFirstParticipantMe ? participants[1]['userName'] : participants[0]['userName'];
    }
    return "Chat";
  }

  String getPartnerId(dynamic conversation) {
    if (conversation['participants']?.length == 2) {
      final participants = conversation['participants'];
      // Find the participant that is not the current user
      return participants.firstWhere(
        (p) => p['_id'] != currentUserId,
        orElse: () => {'_id': 'unknown'},
      )['_id'];
    }
    return "unknown";
  }

  void markConversationAsRead(String conversationId) {
    final conversation = conversations.firstWhere(
      (c) => c['_id'] == conversationId,
      orElse: () => null,
    );
    
    if (conversation != null && conversation['messages']?.isNotEmpty == true) {
      final lastMessageId = conversation['messages'].last['_id'].toString();
      lastReadMessageIds[conversationId] = lastMessageId;
      _saveLastReadMessageIds();
      
      // Update unread counts
      setState(() {
        _updateUnreadCounts();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchConversations,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty && conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $errorMessage'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: fetchConversations,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final conversationId = conversation['_id'];
                    final title = getPartnerName(conversation);
                    final partnerId = getPartnerId(conversation);
                    final lastMessage = conversation['messages']?.isNotEmpty == true
                        ? conversation['messages'].last['text']
                        : 'No messages';
                    final lastMessageTime = conversation['messages']?.isNotEmpty == true
                        ? DateFormat('HH:mm').format(
                            DateTime.parse(conversation['messages'].last['createdAt']))
                        : '';
                    final unreadCount = unreadMessageCounts[conversationId] ?? 0;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.shade200,
                        child: profilePictures.containsKey(partnerId)
                            ? ClipOval(
                                child: Image.memory(
                                  profilePictures[partnerId]!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(Icons.person, color: Colors.grey.shade600),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            lastMessageTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: unreadCount > 0 
                                  ? Colors.blue.shade700 
                                  : Colors.grey.shade600,
                            ),
                          ),
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        // Mark as read when opening the conversation
                        markConversationAsRead(conversationId);
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              conversationId: conversationId,
                              partnerNames: title,
                              partnerId: partnerId,
                            ),
                          ),
                        ).then((_) => fetchConversations());
                      },
                    );
                  },
                ),
    );
  }
}