import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cuqter/main.dart';
import 'package:cuqter/Screen/chat/chat_screen.dart';
import 'package:cuqter/Screen/calls/call_screen.dart';
import 'package:cuqter/Screen/home/notification_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';

/// Top-level background action handler for notification taps (must be a top-level or static function)
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.actionId == 'reply_action' &&
      response.input != null &&
      response.input!.isNotEmpty) {
    final text = response.input!;
    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final chatId = data['chatId'];
      final originalSenderId = data['senderId'];
      final originalReceiverId = data['receiverId'];

      // When replying from notification, the sender of the reply is the original receiver (us)
      // and the receiver of the reply is the original sender.
      final senderId = originalReceiverId;
      final receiverId = originalSenderId;

      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: "AIzaSyBOvtzNFHyoCeq8pZZ_JdaG0dmd4a1DPHs",
              authDomain: "cuqter-2fa01.firebaseapp.com",
              databaseURL: "https://cuqter-2fa01-default-rtdb.firebaseio.com",
              projectId: "cuqter-2fa01",
              storageBucket: "cuqter-2fa01.firebasestorage.app",
              messagingSenderId: "921725231252",
              appId: "1:921725231252:web:a2dbfa0c97694cbf299481",
              measurementId: "G-5TKLZ0RS2M",
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
            'senderId': senderId,
            'receiverId': receiverId,
            'text': text,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'type': 'text',
          });

      // Ensure both users are in each other's contacts so they appear on the homepage
      await FirebaseFirestore.instance.collection('users').doc(senderId).set({
        'contacts': FieldValue.arrayUnion([receiverId]),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('users').doc(receiverId).set({
        'contacts': FieldValue.arrayUnion([senderId]),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('Background inline reply sent successfully: $text');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling background inline reply: $e');
      }
    }
  } else if (response.actionId == 'accept_call' ||
      response.actionId == 'decline_call' ||
      (response.payload?.contains('"incoming_call"') ?? false)) {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: "AIzaSyBOvtzNFHyoCeq8pZZ_JdaG0dmd4a1DPHs",
              authDomain: "cuqter-2fa01.firebaseapp.com",
              databaseURL: "https://cuqter-2fa01-default-rtdb.firebaseio.com",
              projectId: "cuqter-2fa01",
              storageBucket: "cuqter-2fa01.firebasestorage.app",
              messagingSenderId: "921725231252",
              appId: "1:921725231252:web:a2dbfa0c97694cbf299481",
              measurementId: "G-5TKLZ0RS2M",
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }

      if (response.payload != null) {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        if (data['type'] == 'incoming_call') {
          final roomId = data['roomId'];
          final callerName = data['callerName'] ?? 'Unknown';
          final callerId = data['callerId'] ?? '';
          final isVideoCall = data['isVideoCall'] ?? false;

          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await FirebaseDatabase.instance
                .ref('incoming_calls/${currentUser.uid}')
                .remove();
          }

          if (roomId != null) {
            await FlutterCallkitIncoming.endCall(roomId);
            await NotificationService.localNotifications.cancel(
              id: roomId.hashCode & 0x7FFFFFFF,
            );
          }

          if (response.actionId == 'decline_call') {
            if (roomId != null) {
              await FirebaseDatabase.instance.ref('calls/$roomId').remove();
            }
            return;
          }

          // Otherwise accept call
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigatorKey.currentState?.popUntil((route) => route.isFirst);
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => CallScreen(
                  roomId: roomId,
                  isVideoCall: isVideoCall,
                  receiverName: callerName,
                  receiverId: callerId,
                ),
              ),
            );
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling background call action: $e');
      }
    }
  }
}

Future<Uint8List?> _getProfilePicBytes(String? pathOrUrl) async {
  if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
  try {
    if (pathOrUrl.startsWith('http')) {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.getUrl(
        Uri.parse(pathOrUrl),
      );
      final HttpClientResponse response = await request.close();
      if (response.statusCode == 200) {
        final List<int> bytes = await response.fold<List<int>>(
          [],
          (previous, element) => previous..addAll(element),
        );
        return Uint8List.fromList(bytes);
      }
    } else if (pathOrUrl.startsWith('assets/')) {
      try {
        final byteData = await rootBundle.load(pathOrUrl);
        return byteData.buffer.asUint8List();
      } catch (e) {
        if (kDebugMode) {
          print('Error loading asset in isolate: $e');
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error getting profile pic bytes: $e');
    }
  }
  return null;
}

@pragma('vm:entry-point')
Future<void> showMessageNotification(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) {
      if (kDebugMode) {
        print(
          'Web message received: ${message.notification?.title} - ${message.notification?.body}',
        );
      }
      // Show a visual notification using a SnackBar since local_notifications isn't supported on web
      if (navigatorKey.currentContext != null) {
        final title =
            message.notification?.title ??
            message.data['title'] ??
            'New Message';
        final bodyText =
            message.notification?.body ?? message.data['body'] ?? '';

        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (bodyText.isNotEmpty) Text(bodyText),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // You can add navigation logic here if needed based on message.data
              },
            ),
          ),
        );
      }
      return;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await NotificationService.initializeLocalNotifications();
    final data = message.data;

    // Resolve title and body from the notification block if available, fallback to data payload
    final String title =
        message.notification?.title ?? data['title'] ?? 'New Message';
    String body = message.notification?.body ?? data['body'] ?? '';
    final String? messageType = data['type'];

    // 1. Handle incoming calls and call cancellations via Full-Screen Intent / CallKit
    if (messageType == 'video_call' ||
        messageType == 'voice_call' ||
        messageType == 'call_invite') {
      final isVideo =
          messageType == 'video_call' || data['isVideoCall'] == 'true';
      await NotificationService.showIncomingCallNotification(
        callerName: data['callerName'] ?? title,
        roomId: data['roomId'] ?? body,
        callerId: data['callerId'] ?? data['senderId'] ?? '',
        isVideoCall: isVideo,
        callerPic: data['callerPic'] ?? data['senderProfilePic'],
      );
      return; // Skip showing chat notification
    }

    if (messageType == 'call_cancel') {
      final roomId = data['roomId'] ?? body;
      if (roomId != null && roomId.isNotEmpty) {
        await NotificationService.cancelCallNotification(roomId);
      }
      return;
    }

    // 2. Message deduplication: ignore if this messageId was already processed
    final messageId = message.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      if (NotificationService._recentlyProcessedMessageIds.contains(messageId)) {
        return;
      }
      NotificationService._recentlyProcessedMessageIds.add(messageId);
      if (NotificationService._recentlyProcessedMessageIds.length > 100) {
        NotificationService._recentlyProcessedMessageIds.remove(
          NotificationService._recentlyProcessedMessageIds.first,
        );
      }
    }

    // 3. Skip notification if user is actively viewing this chat conversation
    final senderId = data['senderId'];
    if (senderId != null && senderId == NotificationService.activeChatUserId) {
      return;
    }

    // 4. On iOS, setForegroundNotificationPresentationOptions already shows the banner
    // if a notification payload was present. Skip local notification to prevent duplicate banners.
    if (!kIsWeb && Platform.isIOS && message.notification != null) {
      return;
    }

    if (messageType == 'friend_request') {
      const androidDetails = AndroidNotificationDetails(
        'friend_requests_channel',
        'Friend Requests',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );
      const iosDetails = DarwinNotificationDetails(
        categoryIdentifier: 'friend_requests_category',
      );
      await NotificationService.localNotifications.show(
        id: data['senderId'].hashCode & 0x7FFFFFFF,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: jsonEncode({'type': 'friend_request'}),
      );
      return;
    }

    // Client-side fallback: if body looks like a URL or is empty, show a friendly type label
    if (messageType != null && messageType != 'text') {
      switch (messageType) {
        case 'image':
          body = '📷 Photo';
          break;
        case 'video':
          body = '🎥 Video';
          break;
        case 'audio':
          body = '🎵 Audio';
          break;
        case 'document':
          body = '📄 Document';
          break;
        case 'location':
          body = '📍 Shared a location';
          break;
      }
    } else if (body.startsWith('http')) {
      // Legacy: body is a raw URL, convert based on URL pattern
      final lower = body.toLowerCase();
      if (lower.contains('/image/upload') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.jpeg')) {
        body = '📷 Photo';
      } else if (lower.contains('/video/upload') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov')) {
        body = '🎥 Video';
      } else if (lower.endsWith('.mp3') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.wav')) {
        body = '🎵 Audio';
      } else if (lower.contains('/raw/upload') ||
          lower.endsWith('.pdf') ||
          lower.endsWith('.doc')) {
        body = '📄 Document';
      } else {
        body = '📎 Shared a file';
      }
    } else {
      // Strip any pipe-separated filesize from text messages
      body = body.split('|').first;
    }
    final chatId = data['chatId'];
    final receiverId = data['receiverId'];

    // 1. Fetch sender's profile picture (use payload directly, fallback to Firestore)
    String? profilePicUrl = data['senderProfilePic'];
    if ((profilePicUrl == null || profilePicUrl.isEmpty) && senderId != null) {
      try {
        final senderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(senderId)
            .get();
        if (senderDoc.exists && senderDoc.data() != null) {
          profilePicUrl = senderDoc.data()!['profilepic'];
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error fetching sender document in background: $e');
        }
      }
    }

    // 2. Download profile image bytes
    Uint8List? profilePicBytes;
    if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
      profilePicBytes = await _getProfilePicBytes(profilePicUrl);
    }

    // 3. Write to temporary file for FilePathAndroidBitmap and DarwinNotificationAttachment
    String? tempFilePath;
    if (profilePicBytes != null) {
      try {
        final tempDir = Directory.systemTemp;
        final file = File(
          '${tempDir.path}/notification_profile_${senderId ?? 'user'}.jpg',
        );
        await file.writeAsBytes(profilePicBytes);
        tempFilePath = file.path;
      } catch (e) {
        if (kDebugMode) {
          print('Error saving temp notification image: $e');
        }
      }
    }

    // 4. Configure Android Messaging Style & Person Details
    final Person senderPerson = Person(
      name: title,
      key: senderId,
      icon: profilePicBytes != null
          ? ByteArrayAndroidIcon(profilePicBytes)
          : null,
    );

    final Message messageItem = Message(body, DateTime.now(), senderPerson);

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      senderPerson,
      messages: [messageItem],
    );

    // Initialize local notifications if not already done in this isolate
    await NotificationService.initializeLocalNotifications();

    // Configure Android Inline Reply Actions
    final List<AndroidNotificationAction> androidActions = [
      const AndroidNotificationAction(
        'reply_action',
        'Reply',
        inputs: [AndroidNotificationActionInput(label: 'Type your reply...')],
        showsUserInterface: false,
      ),
    ];

    // Payload containing metadata to identify the thread and parties
    final payloadData = {
      'chatId': chatId,
      'senderId': senderId,
      'receiverId': receiverId,
      'title': title,
    };

    // Present the Notification
    await NotificationService.localNotifications.show(
      id: message.messageId.hashCode & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'chats_messages_channel',
          'Chat Messages',
          channelDescription:
              'This channel is used for real-time chat message push notifications.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          largeIcon: tempFilePath != null
              ? FilePathAndroidBitmap(tempFilePath)
              : null,
          playSound: true,
          actions: androidActions,
          styleInformation: messagingStyle,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'chats_messages_category',
          attachments: tempFilePath != null
              ? [DarwinNotificationAttachment(tempFilePath)]
              : null,
        ),
      ),
      payload: jsonEncode(payloadData),
    );
  } catch (e) {
    if (kDebugMode) {
      print('Error displaying notification in isolate: $e');
    }
  }
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _isLocalNotificationsInitialized = false;

  /// User ID of the currently active chat screen (used to suppress notifications for active conversation)
  static String? activeChatUserId;
  static String? activeChatId;

  /// Tracks current ringing room to eliminate duplicate call triggers
  static String? _activeRingingRoomId;

  /// LRU cache of recently processed message IDs to eliminate duplicates
  static final Set<String> _recentlyProcessedMessageIds = <String>{};

  static void _handleLocalNotificationClick(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);

        if (data['type'] == 'friend_request') {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (context) => const NotificationScreen()),
          );
          return;
        }

        final chatId = data['chatId'];
        final senderId = data['senderId'];
        final senderName = data['title'] ?? 'Chat';

        if (chatId != null && senderId != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                receiverId: senderId,
                receiverName: senderName,
                receiverProfilePic: data['profilePic'] ?? data['profilepic'],
              ),
            ),
          );
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error handling local notification click: $e');
        }
      }
    }
  }

  static Future<void> _handleCallNotificationAction(
    NotificationResponse response,
  ) async {
    try {
      if (response.payload != null) {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        if (data['type'] == 'incoming_call') {
          final roomId = data['roomId'];
          final callerName = data['callerName'];
          final callerId = data['callerId'];
          final isVideoCall = data['isVideoCall'] ?? false;

          // Stop ringing by removing node
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await FirebaseDatabase.instance
                .ref('incoming_calls/${currentUser.uid}')
                .remove();
          }

          if (roomId != null) {
            await FlutterCallkitIncoming.endCall(roomId);
            await localNotifications.cancel(id: roomId.hashCode & 0x7FFFFFFF);
          }

          if (response.actionId == 'decline_call') {
            if (roomId != null) {
              await FirebaseDatabase.instance.ref('calls/$roomId').remove();
            }
            return; // Just decline
          }

          // Otherwise accept or tapped notification
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => CallScreen(
                roomId: roomId,
                isVideoCall: isVideoCall,
                receiverName: callerName,
                receiverId: callerId,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error handling call action: $e');
    }
  }

  static Future<void> showIncomingCallNotification({
    required String callerName,
    required String roomId,
    required String callerId,
    required bool isVideoCall,
    String? callerPic,
  }) async {
    if (kIsWeb) return;

    // Eliminate duplicate alerts: if this call is already ringing, ignore repeat triggers
    if (_activeRingingRoomId == roomId) {
      if (kDebugMode) {
        print('Call $roomId is already ringing. Skipping duplicate alert.');
      }
      return;
    }
    _activeRingingRoomId = roomId;

    String finalCallerName = callerName;
    String? finalAvatarUrl = callerPic;

    // Fetch exact user details from Firestore to guarantee actual user photo & name
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(callerId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['name'] != null && (data['name'] as String).isNotEmpty) {
          finalCallerName = data['name'];
        }
        if (data['profilepic'] != null &&
            (data['profilepic'] as String).isNotEmpty) {
          finalAvatarUrl = data['profilepic'];
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error fetching caller notification info: $e');
    }

    final params = CallKitParams(
      id: roomId,
      nameCaller: finalCallerName,
      appName: 'Cuqter',
      avatar: (finalAvatarUrl != null && finalAvatarUrl.isNotEmpty)
          ? finalAvatarUrl
          : null,
      handle: isVideoCall ? 'Incoming Video Call' : 'Incoming Voice Call',
      type: isVideoCall ? 1 : 0,
      duration: 35000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{
        'roomId': roomId,
        'callerId': callerId,
        'callerName': finalCallerName,
        'isVideoCall': isVideoCall,
        'callerPic': finalAvatarUrl ?? '',
      },
      headers: <String, dynamic>{'apiKey': 'v1.0', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowCallID: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    // CallKit triggers Android Full-Screen Intent on Android and native CallKit UI on iOS
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> cancelCallNotification(String roomId) async {
    if (kIsWeb) return;
    if (_activeRingingRoomId == roomId) {
      _activeRingingRoomId = null;
    }
    await FlutterCallkitIncoming.endCall(roomId);
    await localNotifications.cancel(id: roomId.hashCode & 0x7FFFFFFF);
  }

  static Future<void> initializeLocalNotifications() async {
    if (kIsWeb) return;
    if (_isLocalNotificationsInitialized) return;

    final List<DarwinNotificationCategory> darwinCategories = [
      DarwinNotificationCategory(
        'chats_messages_category',
        actions: [
          DarwinNotificationAction.text(
            'reply_action',
            'Reply',
            buttonTitle: 'Send',
            placeholder: 'Type your reply...',
          ),
        ],
      ),
      DarwinNotificationCategory(
        'incoming_call_category',
        actions: [
          DarwinNotificationAction.plain(
            'accept_call',
            'Accept',
            options: {DarwinNotificationActionOption.foreground},
          ),
          DarwinNotificationAction.plain(
            'decline_call',
            'Decline',
            options: {DarwinNotificationActionOption.destructive},
          ),
        ],
      ),
    ];

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(notificationCategories: darwinCategories);

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == 'reply_action' &&
            response.input != null &&
            response.input!.isNotEmpty) {
          notificationTapBackground(response);
        } else if (response.actionId == 'accept_call' ||
            response.actionId == 'decline_call' ||
            (response.payload?.contains('"incoming_call"') ?? false)) {
          _handleCallNotificationAction(response);
        } else {
          _handleLocalNotificationClick(response);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Configure Android High-Importance Channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chats_messages_channel',
      'Chat Messages',
      description:
          'This channel is used for real-time chat message push notifications.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    if (Platform.isAndroid) {
      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'incoming_calls_channel',
        'Incoming Calls',
        description: 'Notifications for incoming audio and video calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(callChannel);

      const AndroidNotificationChannel friendRequestChannel =
          AndroidNotificationChannel(
            'friend_requests_channel',
            'Friend Requests',
            description: 'Notifications for incoming friend requests',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          );
      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(friendRequestChannel);
    }

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      if (event is CallEventActionCallAccept) {
        _activeRingingRoomId = null;
        final body = event.callKitParams;
        final roomId = body.id;
        final extra = body.extra ?? {};
        final callerId = extra['callerId'] ?? '';
        final callerName = extra['callerName'] ?? body.nameCaller ?? 'Unknown';
        final isVideoCall = extra['isVideoCall'] == true;

        // Stop ringing by removing node
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          FirebaseDatabase.instance
              .ref('incoming_calls/${currentUser.uid}')
              .remove();
        }

        if (roomId.isNotEmpty) {
          localNotifications.cancel(id: roomId.hashCode & 0x7FFFFFFF);
        }

        // Ensure CallScreen can push properly
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.popUntil((route) => route.isFirst);
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => CallScreen(
                roomId: roomId,
                receiverId: callerId,
                receiverName: callerName,
                isVideoCall: isVideoCall,
              ),
            ),
          );
        }
      } else if (event is CallEventActionCallDecline ||
          event is CallEventActionCallEnded ||
          event is CallEventActionCallTimeout) {
        _activeRingingRoomId = null;
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          FirebaseDatabase.instance
              .ref('incoming_calls/${currentUser.uid}')
              .remove();
        }
        String roomId = '';
        if (event is CallEventActionCallDecline) {
          roomId = event.callKitParams.id;
        } else if (event is CallEventActionCallEnded) {
          roomId = event.callKitParams.id;
        } else if (event is CallEventActionCallTimeout) {
          roomId = event.id;
        }
        if (roomId.isNotEmpty) {
          FirebaseDatabase.instance.ref('calls/$roomId').remove();
          localNotifications.cancel(id: roomId.hashCode & 0x7FFFFFFF);
        }
      } else if (event is CallEventActionDidUpdateDevicePushTokenVoip) {
        try {
          final String? token =
              await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          if (token != null && token.isNotEmpty) {
            await NotificationService()._updateVoipTokenInFirestore(token);
          }
        } catch (e) {
          if (kDebugMode) print('Error updating VoIP token: $e');
        }
      }
    });

    _isLocalNotificationsInitialized = true;
  }

  /// Initializes permissions, retrieves tokens, and sets up message listeners.
  Future<void> initialize() async {
    // 1. Initialize local notifications for early callback registration (main isolate)
    await initializeLocalNotifications();
    // Enable foreground notification alerts (banners/sound/badge)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Request notification permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Request Android local notification permissions explicitly on Android 13+
    if (!kIsWeb && Platform.isAndroid) {
      await localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      if (kDebugMode) {
        print(
          'Notification permissions granted: ${settings.authorizationStatus}',
        );
      }

      // 2. Fetch and save active device token
      await saveDeviceToken();

      // 3. Handle token refreshes in the future
      _fcm.onTokenRefresh.listen((newToken) async {
        await _updateTokenInFirestore(newToken);
      });

      // 4. Handle Foreground Messages (Fires when app is open)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Foreground message received: ${message.messageId}');
        }
        showMessageNotification(message);
      });

      // 5. Handle notification tap when app is in background but not terminated
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print(
            'App opened from background notification: ${message.messageId}',
          );
        }
        _handleNotificationClick(message);
      });

      // 6. Handle notification tap when app was completely terminated
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          print(
            'App launched from terminated state via notification: ${initialMessage.messageId}',
          );
        }
        _handleNotificationClick(initialMessage);
      }

      // 7. Handle app launch from terminated state via local notification tap
      final NotificationAppLaunchDetails? notificationAppLaunchDetails =
          await localNotifications.getNotificationAppLaunchDetails();
      if (notificationAppLaunchDetails != null &&
          notificationAppLaunchDetails.didNotificationLaunchApp) {
        final NotificationResponse? response =
            notificationAppLaunchDetails.notificationResponse;
        if (response != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (response.actionId == 'accept_call' ||
                response.actionId == 'decline_call' ||
                (response.payload?.contains('"incoming_call"') ?? false)) {
              _handleCallNotificationAction(response);
            } else {
              _handleLocalNotificationClick(response);
            }
          });
        }
      }

      // 8. Handle app launch from terminated state via CallKit accept action
      if (!kIsWeb) {
        try {
          final dynamic activeCalls = await FlutterCallkitIncoming.activeCalls();
          if (activeCalls is List && activeCalls.isNotEmpty) {
            final firstCall = activeCalls.first;
            if (firstCall is Map && firstCall['accepted'] == true) {
              final roomId = firstCall['id'] as String? ?? '';
              final extra = (firstCall['extra'] as Map?) ?? {};
              final callerId = extra['callerId'] as String? ?? '';
              final callerName = extra['callerName'] as String? ??
                  firstCall['nameCaller'] as String? ??
                  'Unknown';
              final isVideoCall = extra['isVideoCall'] == true;

              if (roomId.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (navigatorKey.currentState != null) {
                    navigatorKey.currentState!.popUntil((route) => route.isFirst);
                    navigatorKey.currentState!.push(
                      MaterialPageRoute(
                        builder: (context) => CallScreen(
                          roomId: roomId,
                          receiverId: callerId,
                          receiverName: callerName,
                          isVideoCall: isVideoCall,
                        ),
                      ),
                    );
                  }
                });
              }
            }
          }
        } catch (e) {
          if (kDebugMode) print('Error checking active CallKit calls on launch: $e');
        }
      }

      // 9. Listen to friend requests locally since cloud functions are unavailable
      _listenForFriendRequests();
    } else {
      if (kDebugMode) {
        print('Notification permissions denied.');
      }
    }
  }

  void _listenForFriendRequests() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    bool isFirstFriendRequestQuery = true;
    FirebaseFirestore.instance
        .collection('friend_requests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
          if (isFirstFriendRequestQuery) {
            isFirstFriendRequestQuery = false;
            return; // Ignore existing requests on startup
          }
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data();
              if (data != null) {
                showMessageNotification(
                  RemoteMessage(
                    data: {
                      'type': 'friend_request',
                      'senderId': data['senderId'],
                      'title': 'New Friend Request',
                      'body':
                          '${data['senderName'] ?? 'Someone'} sent you a friend request',
                    },
                  ),
                );
              }
            }
          }
        });
  }

  /// Logic to handle app navigation/routing when a notification is clicked (not inline replied)
  void _handleNotificationClick(RemoteMessage message) {
    if (kDebugMode) {
      print('Notification clicked, data payload: ${message.data}');
    }
    
    final data = message.data;
    if (data['type'] == 'friend_request') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const NotificationScreen()),
      );
      return;
    }

    final chatId = data['chatId'];
    final senderId = data['senderId'];
    final senderName = data['title'] ?? 'Chat';

    if (chatId != null && senderId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            receiverId: senderId,
            receiverName: senderName,
            receiverProfilePic: data['senderProfilePic'] ?? data['profilepic'],
          ),
        ),
      );
    }
  }

  /// Fetches the active FCM Token and stores it in Firestore.
  /// On iOS, also retrieves the PushKit VoIP token.
  Future<void> saveDeviceToken() async {
    try {
      String? token;
      if (kIsWeb) {
        // NOTE: For web, a vapidKey is highly recommended/required.
        token = await _fcm.getToken(
          vapidKey:
              "BF8MsbUwKvQ6TuATaIWu3j5V_g8vnZ5OjrRYvcHDmBlZaRvC6lqpqw0Q5At0Rj0WLq9mUjTXVfmbZbOhFPUliGg",
        );
      } else {
        token = await _fcm.getToken();
      }

      if (token != null) {
        await _updateTokenInFirestore(token);
      }

      // iOS Apple PushKit VoIP token
      if (!kIsWeb && Platform.isIOS) {
        try {
          final voipToken =
              await FlutterCallkitIncoming.getDevicePushTokenVoIP();
          if (voipToken != null && voipToken.isNotEmpty) {
            await _updateVoipTokenInFirestore(voipToken);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error getting PushKit VoIP token: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting device tokens: $e');
      }
    }
  }

  /// Persists FCM token to Firestore users collection
  Future<void> _updateTokenInFirestore(String token) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await _firestore.collection('users').doc(currentUser.uid).update({
          'fcmToken': token,
        });
        if (kDebugMode) {
          print('FCM Token successfully stored to Firestore: $token');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving FCM token to Firestore: $e');
      }
    }
  }

  /// Persists iOS PushKit VoIP token to Firestore users collection
  Future<void> _updateVoipTokenInFirestore(String voipToken) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null && voipToken.isNotEmpty) {
        await _firestore.collection('users').doc(currentUser.uid).update({
          'voipToken': voipToken,
        });
        if (kDebugMode) {
          print('PushKit VoIP Token successfully stored to Firestore: $voipToken');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving VoIP token to Firestore: $e');
      }
    }
  }
}
