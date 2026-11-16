import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  static const String _deviceIdKey = 'local_device_id';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _cachedDeviceId;

  /// Retrieves or generates a persistent unique ID for this app installation
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Helper to get human readable device info (model and OS version)
  Future<Map<String, String>> getDeviceMetadata() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String model = 'Unknown Device';
    String os = 'Unknown OS';

    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        model = '${webInfo.browserName.name} Browser';
        os = 'Web (${webInfo.platform ?? "Online"})';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        model = '${androidInfo.brand} ${androidInfo.model}'.trim();
        os = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        model = iosInfo.name;
        os = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        model = windowsInfo.computerName.isNotEmpty
            ? windowsInfo.computerName
            : 'Windows PC';
        os = 'Windows';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        model = macInfo.computerName.isNotEmpty ? macInfo.computerName : 'Mac';
        os = 'macOS ${macInfo.osRelease}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        model = linuxInfo.name;
        os = 'Linux';
      }
    } catch (e) {
      debugPrint('Error getting device metadata: $e');
    }

    return {'model': model, 'os': os};
  }

  /// Retrieves the current FCM token
  Future<String?> getFcmToken() async {
    try {
      if (kIsWeb) {
        return await FirebaseMessaging.instance.getToken(
          vapidKey:
              "BF8MsbUwKvQ6TuATaIWu3j5V_g8vnZ5OjrRYvcHDmBlZaRvC6lqpqw0Q5At0Rj0WLq9mUjTXVfmbZbOhFPUliGg",
        );
      } else {
        return await FirebaseMessaging.instance.getToken();
      }
    } catch (e) {
      debugPrint('Error fetching FCM token in SessionService: $e');
      return null;
    }
  }

  /// Tracks active device on login / app startup under users/{uid}/devices/{deviceId}
  Future<void> recordLoginSession(String uid) async {
    try {
      final deviceId = await getDeviceId();
      final metadata = await getDeviceMetadata();
      final fcmToken = await getFcmToken();

      final deviceRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId);

      final docSnapshot = await deviceRef.get();
      final isNewDevice = !docSnapshot.exists;

      final deviceData = {
        'deviceId': deviceId,
        'deviceModel': metadata['model'] ?? 'Unknown Device',
        'deviceName': metadata['model'] ?? 'Unknown Device',
        'deviceOs': metadata['os'] ?? 'Unknown OS',
        'osVersion': metadata['os'] ?? 'Unknown OS',
        'fcmToken': fcmToken ?? '',
        'loginTimestamp': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
        'isCurrent': true,
      };

      // Store in users/{uid}/devices/{deviceId}
      await deviceRef.set(deviceData, SetOptions(merge: true));

      // Also mirror to users/{uid}/sessions/{deviceId} for backwards compatibility
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(deviceId)
          .set(deviceData, SetOptions(merge: true));

      // If a new device has logged in, trigger login alert push notification to other devices
      if (isNewDevice) {
        await _sendLoginAlertToOtherDevices(
          uid: uid,
          currentDeviceId: deviceId,
          deviceModel: metadata['model'] ?? 'Unknown Device',
          deviceOs: metadata['os'] ?? 'Unknown OS',
        );
      }
    } catch (e) {
      debugPrint('Failed to record login session: $e');
    }
  }

  /// Sends login alert notification to other existing device tokens
  Future<void> _sendLoginAlertToOtherDevices({
    required String uid,
    required String currentDeviceId,
    required String deviceModel,
    required String deviceOs,
  }) async {
    try {
      final devicesSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .get();

      final otherTokens = <String>[];
      for (final doc in devicesSnapshot.docs) {
        if (doc.id != currentDeviceId) {
          final token = doc.data()['fcmToken']?.toString();
          if (token != null && token.isNotEmpty) {
            otherTokens.add(token);
          }
        }
      }

      final notificationId =
          'login_alert_${currentDeviceId}_${DateTime.now().millisecondsSinceEpoch}';

      const alertTitle = 'Security Alert: New Login';
      final alertBody = 'New login detected from $deviceModel ($deviceOs)';

      // Write notification record to Firestore
      await _firestore.collection('notifications').doc(notificationId).set({
        'notificationId': notificationId,
        'type': 'login_alert',
        'senderId': 'system',
        'senderName': 'Security Alert',
        'senderProfilePic': '',
        'receiverId': uid,
        'title': alertTitle,
        'body': alertBody,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'deviceId': currentDeviceId,
        'deviceModel': deviceModel,
        'deviceOs': deviceOs,
        'targetTokens': otherTokens,
      });

      if (kDebugMode) {
        print(
          'Login alert generated for $uid. Other device tokens notified: ${otherTokens.length}',
        );
      }
    } catch (e) {
      debugPrint('Error sending login alert: $e');
    }
  }

  /// Deletes a specific device session (used for remote logout)
  Future<void> logoutDevice(String uid, String targetDeviceId) async {
    try {
      await Future.wait([
        _firestore
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(targetDeviceId)
            .delete(),
        _firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(targetDeviceId)
            .delete(),
      ]);
    } catch (e) {
      debugPrint('Failed to delete session: $e');
    }
  }

  /// Deletes all devices except current device
  Future<void> logoutAllOtherDevices(String uid) async {
    try {
      final currentDeviceId = await getDeviceId();
      final devicesSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .get();

      for (final doc in devicesSnapshot.docs) {
        if (doc.id != currentDeviceId) {
          await logoutDevice(uid, doc.id);
        }
      }
    } catch (e) {
      debugPrint('Failed to logout all other devices: $e');
    }
  }

  /// Deletes the current device's session during explicit local logout
  Future<void> removeCurrentSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final deviceId = await getDeviceId();
      await logoutDevice(user.uid, deviceId);
    } catch (e) {
      debugPrint('Failed to remove current session: $e');
    }
  }

  /// Clears local session cache
  Future<void> clearLocalSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_profile_name');
      await prefs.remove('cached_profile_username');
      await prefs.remove('cached_profile_bio');
      await prefs.remove('cached_profile_pic');
    } catch (_) {}
  }
}
