import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart' show DateFormat; // explicit import of DateFormat

// Chat List Screen: Fetch and display all conversations for the authenticated user.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> conversations = [];
  bool isLoading = true;
  String errorMessage = '';
  String currentUserName = '';
  Map<String, int> unreadCounts = {}; // stores unread count per conversation
  Timer? _pollingTimer; // new: automatically refresh chat list

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName().then((_) {
      fetchConversations().then((_) {
        updateUnreadCounts();
      });
    });

    // Start a periodic timer to refresh conversations
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await fetchConversations();
      await updateUnreadCounts();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUserName() async {
    // Try reading from secure storage first.
    String? name = await _secureStorage.read(key: 'userName');
    if (name != null && name.isNotEmpty) {
      setState(() {
        currentUserName = name;
      });
    } else {
      // If not available, fetch current user details from the server.
      String? authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie != null) {
        final response = await http.get(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['user'] != null) {
            setState(() {
              currentUserName = data['user']['userName'] ?? '';
            });
            // Optionally, save the userName locally for future use.
            await _secureStorage.write(key: 'userName', value: currentUserName);
          }
        }
      }
    }
  }

  Future<void> fetchConversations() async {
    try {
      // Retrieve auth cookie from secure storage.
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        setState(() {
          errorMessage = 'Not authenticated';
          isLoading = false;
        });
        return;
      }
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            conversations = data['conversations'];
            // Sort conversations so that the conversation with the newest
            // last message comes first.
            conversations.sort((a, b) {
              DateTime aTime = DateTime.fromMillisecondsSinceEpoch(0);
              DateTime bTime = DateTime.fromMillisecondsSinceEpoch(0);
              if (a['messages'] != null && a['messages'].isNotEmpty) {
                aTime = DateTime.parse(a['messages'].last['createdAt']);
              }
              if (b['messages'] != null && b['messages'].isNotEmpty) {
                bTime = DateTime.parse(b['messages'].last['createdAt']);
              }
              return bTime.compareTo(aTime);
            });
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = data['error'] ?? 'Failed to fetch conversations';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Server error: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  // New: update unreadCounts for each conversation by comparing stored lastRead time.
  Future<void> updateUnreadCounts() async {
    Map<String, int> counts = {};
    for (var conv in conversations) {
      String convId = conv['_id'];
      // Read last read timestamp; default to epoch if missing.
      String? lastReadStr = await _secureStorage.read(key: 'lastRead_$convId');
      DateTime lastRead = lastReadStr != null ? DateTime.parse(lastReadStr) : DateTime.fromMillisecondsSinceEpoch(0);
      int count = 0;
      if (conv['messages'] != null) {
        for (var msg in conv['messages']) {
          if (msg['sender'] != null &&
              msg['sender']['userName'] != currentUserName) {
            DateTime msgTime = DateTime.parse(msg['createdAt']);
            if (msgTime.isAfter(lastRead)) {
              count++;
            }
          }
        }
      }
      counts[convId] = count;
    }
    setState(() {
      unreadCounts = counts;
    });
  }

  // Updated getPartnerName: returns the other user's name by comparing current user name.
  String getPartnerName(dynamic conversation) {
    if (conversation['participants'] != null &&
        conversation['participants'] is List &&
        conversation['participants'].length == 2 &&
        currentUserName.isNotEmpty) {
      final participant0 = conversation['participants'][0];
      final participant1 = conversation['participants'][1];
      // If currentUserName matches participant0, then partner is participant1, else vice versa.
      return (participant0['userName'] == currentUserName)
          ? participant1['userName']
          : participant0['userName'];
    }
    return "Chat";
  }

  // Function to create a new conversation using the given identifier.
  Future<void> createConversation(String identifier) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Not authenticated')));
        return;
      }
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
        body: json.encode({'identifier': identifier}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['conversation'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: data['conversation']['_id'],
                partnerNames: getPartnerName(data['conversation']),
              ),
            ),
          );
          // Optionally, refresh conversation list.
          fetchConversations();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['error'] ?? 'Failed to create conversation')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server error: ${response.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // Function to show a dialog to enter the partner's identifier.
  void showNewChatDialog() {
    final identifierController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Chat'),
          content: TextField(
            controller: identifierController,
            decoration: const InputDecoration(
              hintText: 'Enter user identifier',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final identifier = identifierController.text.trim();
                if (identifier.isNotEmpty) {
                  Navigator.pop(context); // close the dialog
                  createConversation(identifier);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: showNewChatDialog,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(child: Text('Error: $errorMessage'))
              : ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    String title = getPartnerName(conversation);
                    String lastMessage =
                        conversation['messages'] != null && conversation['messages'].isNotEmpty
                            ? conversation['messages'].last['text']
                            : 'No messages yet';
                    int unreadCount = unreadCounts[conversation['_id']] ?? 0;
                    String lastMessageTime = '';
                    if (conversation['messages'] != null &&
                        conversation['messages'].isNotEmpty) {
                      lastMessageTime = formatTimestamp(conversation['messages'].last['createdAt']);
                    }
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(title),
                      subtitle: Text(lastMessage),
                      trailing: Text(
                        lastMessageTime,
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      onTap: () async {
                        // When opening, update last read timestamp.
                        await _secureStorage.write(
                          key: 'lastRead_${conversation['_id']}',
                          value: DateTime.now().toIso8601String(),
                        );
                        // Navigate to ChatScreen.
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              conversationId: conversation['_id'],
                              partnerNames: title,
                            ),
                          ),
                        );
                        // When returning, refresh conversations and unread counts.
                        await fetchConversations();
                        await updateUnreadCounts();
                      },
                    );
                  },
                ),
    );
  }
}

// Chat Screen: Displays messages of a conversation and allows sending new messages.
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String partnerNames;
  final String? sellerId; // Add this

  const ChatScreen({
    super.key, 
    required this.conversationId, 
    required this.partnerNames,
    this.sellerId, // Add this
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> messages = [];
  List<Message> pendingMessages = [];
  bool isLoading = true;
  String errorMessage = '';
  final TextEditingController _messageController = TextEditingController();
  Timer? _pollingTimer;
  String currentUserName = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName().then((_) {
      if (widget.sellerId != null) {
        // If sellerId is provided, create a new conversation
        _createConversation();
      } else {
        // Otherwise fetch existing conversation
        fetchConversation();
      }
    });
  }

  Future<void> _createConversation() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({'participantId': widget.sellerId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['conversation'] != null) {
          // Use the new conversation ID to fetch messages
          String newConversationId = data['conversation']['_id'];
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: newConversationId,
                partnerNames: widget.partnerNames,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error creating conversation: $e');
    }
  }

  Future<void> _loadCurrentUserName() async {
    String? name = await _secureStorage.read(key: 'userName');
    if (name != null && name.isNotEmpty) {
      setState(() {
        currentUserName = name;
      });
    } else {
      String? authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie != null) {
        final response = await http.get(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['user'] != null) {
            setState(() {
              currentUserName = data['user']['userName'] ?? '';
            });
            await _secureStorage.write(key: 'userName', value: currentUserName);
          }
        }
      }
    }
  }

  Future<void> fetchConversation() async {
    // First, load cached conversation from device memory.
    final String? cached = await _secureStorage.read(key: 'cached_messages_${widget.conversationId}');
    if (cached != null) {
      final cachedMessages = json.decode(cached);
      setState(() {
        messages = cachedMessages;
        isLoading = false;
      });
    }

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        setState(() {
          errorMessage = 'Not authenticated';
          isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final newMessages = data['conversation']['messages'] ?? [];

          // For each pending message we previously added optimistically:
          for (var pending in pendingMessages) {
            bool found = newMessages.any((msg) =>
                msg['text'] == pending.text &&
                msg['createdAt'] == pending.createdAt);
            if (found) {
              // Mark as delivered (remove from pending list)
              pending.isPending = false;
            } else {
              // If still not in confirmed messages, add it so it remains visible.
              newMessages.add(pending.toMap());
            }
          }
          setState(() {
            messages = newMessages;
            isLoading = false;
            errorMessage = '';
          });
          // Cache updated conversation locally.
          await _secureStorage.write(
              key: 'cached_messages_${widget.conversationId}',
              value: json.encode(newMessages));
        } else {
          setState(() {
            errorMessage = data['error'] ?? 'Failed to fetch conversation';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Server error: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> sendMessage() async {
    final trimmedText = _messageController.text.trim();
    if (trimmedText.isEmpty) return;

    // Create an optimistic pending message.
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final nowIso = DateTime.now().toIso8601String();
    final optimisticMessage = Message(
      id: tempId,
      text: trimmedText,
      senderName: currentUserName,
      createdAt: nowIso,
      isPending: true,
    );

    // Immediately add the message to our messages list and clear the TextField.
    setState(() {
      messages = [...messages, optimisticMessage.toMap()];
      pendingMessages.add(optimisticMessage);
      _messageController.clear();
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Not authenticated')));
        return;
      }

      final response = await http.post(
        Uri.parse(
            'https://olx-for-iitrpr-backend.onrender.com/api/conversations/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
        body: json.encode({'text': trimmedText}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // On successful send, remove the pending flag from that message.
          setState(() {
            pendingMessages.removeWhere((m) => m.id == tempId);
          });
          // Refresh the conversation—this will update the pending message with confirmed data.
          await fetchConversation();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Failed to send message')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  // Aligns messages: right for current user, left for partner.
  Widget buildMessageItem(dynamic message, {bool isPending = false}) {
    final bool isSentByMe = message['sender'] != null &&
        message['sender']['userName'] == currentUserName;
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isSentByMe ? Colors.blue[200] : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment:
                  isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  message['text'] ?? '',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  message['createdAt'] != null
                      ? formatTimestamp(message['createdAt'])
                      : '',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
            if (isSentByMe && isPending) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.access_time,
                size: 12,
                color: Colors.black54,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.partnerNames),
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                    ? Center(child: Text('Error: $errorMessage'))
                    : messages.isEmpty
                        ? const Center(child: Text('Nothing here to display'))
                        : ListView.builder(
                            reverse: true,
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message =
                                  messages[messages.length - index - 1];
                              final isPending = pendingMessages.any((m) =>
                                  m.id == (message['_id'] ?? message['id'])); // compare id from server or optimistic message id
                              return buildMessageItem(message, isPending: isPending);
                            },
                          ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Example Message model for optimistic sending
class Message {
  final String id; // temporary id when pending or real _id from server
  final String text;
  final String senderName;
  final String createdAt; // ISO String
  bool isPending;

  Message({
    required this.id,
    required this.text,
    required this.senderName,
    required this.createdAt,
    this.isPending = true,
  });

  // Converts Message to Map to match server data format
  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'text': text,
      'sender': {'userName': senderName},
      'createdAt': createdAt,
    };
  }
}

String formatTimestamp(String isoTime) {
  DateTime messageTime = DateTime.parse(isoTime).toLocal();
  DateTime now = DateTime.now();
  if (messageTime.year == now.year &&
      messageTime.month == now.month &&
      messageTime.day == now.day) {
    // Today: show time only.
    return DateFormat('HH:mm').format(messageTime);
  } else if (messageTime.year == now.year &&
      messageTime.month == now.month &&
      messageTime.day == now.day - 1) {
    // Yesterday.
    return 'Yesterday';
  } else {
    // Else show date.
    return DateFormat('dd MMM yyyy').format(messageTime);
  }
}
