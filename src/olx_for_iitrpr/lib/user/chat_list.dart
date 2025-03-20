import 'dart:convert';
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
  bool isLoading = true;
  String errorMessage = '';
  String currentUserName = '';
  String currentUserId = '';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser().then((_) {
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

  Future<void> _loadLocalConversations() async {
    try {
      final conversationsJson = await _secureStorage.read(key: 'conversations');
      if (conversationsJson != null) {
        setState(() {
          conversations = json.decode(conversationsJson);
          if (isLoading && conversations.isNotEmpty) {
            isLoading = false;
          }
        });
      }
    } catch (e) {
      print('Error loading local conversations: $e');
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
          setState(() {
            conversations = data['conversations'];
            conversations.sort((a, b) {
              final aTime = a['messages']?.isNotEmpty == true
                  ? DateTime.parse(a['messages'].last['createdAt'])
                  : DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = b['messages']?.isNotEmpty == true
                  ? DateTime.parse(b['messages'].last['createdAt'])
                  : DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });
            isLoading = false;
          });
          _saveConversationsLocally();
        }
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
      if (conversations.isEmpty) _loadLocalConversations();
    }
    setState(() => isLoading = false);
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
                    final title = getPartnerName(conversation);
                    final lastMessage = conversation['messages']?.isNotEmpty == true
                        ? conversation['messages'].last['text']
                        : 'No messages';
                    final lastMessageTime = conversation['messages']?.isNotEmpty == true
                        ? DateFormat('HH:mm').format(
                            DateTime.parse(conversation['messages'].last['createdAt']))
                        : '';

                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(title),
                      subtitle: Text(lastMessage),
                      trailing: Text(lastMessageTime),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            conversationId: conversation['_id'],
                            partnerNames: title,
                          ),
                        ),
                      ).then((_) => fetchConversations()),
                    );
                  },
                ),
    );
  }
}
