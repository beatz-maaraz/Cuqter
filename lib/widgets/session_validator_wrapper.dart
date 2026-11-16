import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cuqter/Account/login.dart';
import 'package:cuqter/main.dart';
import 'package:cuqter/services/session_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SessionValidatorWrapper extends StatefulWidget {
  final Widget child;

  const SessionValidatorWrapper({super.key, required this.child});

  @override
  State<SessionValidatorWrapper> createState() =>
      _SessionValidatorWrapperState();
}

class _SessionValidatorWrapperState extends State<SessionValidatorWrapper> {
  StreamSubscription<DocumentSnapshot>? _sessionSub;
  bool _hasConfirmedExistence = false;

  @override
  void initState() {
    super.initState();
    _initSessionListener();
  }

  Future<void> _initSessionListener() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final deviceId = await SessionService().getDeviceId();

      // Ensure session is recorded on startup
      await SessionService().recordLoginSession(user.uid);

      // Listen for remote termination of this device's document
      _sessionSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId)
          .snapshots()
          .listen((doc) async {
            if (doc.exists) {
              _hasConfirmedExistence = true;
            } else if (!doc.exists && _hasConfirmedExistence) {
              // Remote logout detected
              _sessionSub?.cancel();
              _sessionSub = null;

              await FirebaseAuth.instance.signOut();
              await SessionService().clearLocalSession();

              // Navigate back to login
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const Loginpage()),
                (route) => false,
              );

              final navContext = navigatorKey.currentContext;
              if (navContext != null && navContext.mounted) {
                ScaffoldMessenger.of(navContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'You have been logged out remotely from this device.',
                    ),
                    backgroundColor: Colors.redAccent,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            }
          });
    } catch (e) {
      debugPrint('Error starting session listener: $e');
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
