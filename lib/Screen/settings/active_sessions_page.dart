import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cuqter/services/session_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart' as huge;
import 'package:cuqter/utils/custom_snackbar.dart';

class ActiveSessionsPage extends StatefulWidget {
  const ActiveSessionsPage({super.key});

  @override
  State<ActiveSessionsPage> createState() => _ActiveSessionsPageState();
}

class _ActiveSessionsPageState extends State<ActiveSessionsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadCurrentDevice();
  }

  Future<void> _loadCurrentDevice() async {
    final id = await SessionService().getDeviceId();
    if (mounted) {
      setState(() => _currentDeviceId = id);
    }
  }

  Future<void> _logoutAllOtherDevices(List<DocumentSnapshot> sessions) async {
    final user = _auth.currentUser;
    if (user == null || _currentDeviceId == null) return;

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of all other devices?'),
        content: const Text(
          'This will immediately disconnect your account from all other devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (var doc in sessions) {
        if (doc.id != _currentDeviceId) {
          await SessionService().logoutDevice(user.uid, doc.id);
        }
      }
      if (mounted) {
        showCustomSnackBar(context, 'Logged out of all other devices');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: huge.HugeIcon(
            icon: huge.HugeIcons.strokeRoundedArrowLeft01,
            color: colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Active Sessions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('sessions')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No active sessions found.'));
                }

                final sessions = snapshot.data!.docs;
                final otherSessions = sessions
                    .where((doc) => doc.id != _currentDeviceId)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'These are the devices that have logged into your account. You can log out of any unfamiliar devices.',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (otherSessions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton.icon(
                          onPressed: () => _logoutAllOtherDevices(sessions),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.errorContainer,
                            foregroundColor: colorScheme.onErrorContainer,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.logout),
                          label: const Text('Log out of all other devices'),
                        ),
                      ),
                    ],
                    _buildSectionHeader('CURRENT DEVICE', colorScheme),
                    ...sessions
                        .where((doc) => doc.id == _currentDeviceId)
                        .map(
                          (doc) => _buildSessionTile(
                            doc,
                            isCurrent: true,
                            colorScheme: colorScheme,
                          ),
                        ),

                    if (otherSessions.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('OTHER DEVICES', colorScheme),
                      ...otherSessions.map(
                        (doc) => _buildSessionTile(
                          doc,
                          isCurrent: false,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: isDark
              ? colorScheme.onSurface.withValues(alpha: 0.6)
              : colorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _buildSessionTile(
    DocumentSnapshot doc, {
    required bool isCurrent,
    required ColorScheme colorScheme,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = doc.data() as Map<String, dynamic>;
    final deviceName = data['deviceName'] ?? 'Unknown Device';
    final deviceOs = data['deviceOs'] ?? 'Unknown OS';
    final lastActive = data['lastActive'] as Timestamp?;

    String lastActiveText = 'Recently active';
    if (lastActive != null) {
      final date = lastActive.toDate();
      lastActiveText = 'Last active: ${date.day}/${date.month}/${date.year}';
    }

    final Color cardBg = isCurrent
        ? (isDark
            ? colorScheme.primaryContainer.withValues(alpha: 0.25)
            : colorScheme.primary.withValues(alpha: 0.08))
        : (isDark
            ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.65));

    final Color borderColor = isCurrent
        ? colorScheme.primary.withValues(alpha: isDark ? 0.4 : 0.5)
        : (isDark
            ? colorScheme.outlineVariant.withValues(alpha: 0.25)
            : colorScheme.outlineVariant.withValues(alpha: 0.7));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: isCurrent ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isCurrent
                ? colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.12)
                : (isDark
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isCurrent
                  ? colorScheme.primary.withValues(alpha: 0.25)
                  : colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Icon(
            deviceOs.toLowerCase().contains('android')
                ? Icons.android
                : deviceOs.toLowerCase().contains('ios')
                ? Icons.phone_iphone
                : deviceOs.toLowerCase().contains('mac')
                ? Icons.laptop_mac
                : deviceOs.toLowerCase().contains('web')
                ? Icons.web
                : Icons.devices,
            color: isCurrent
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                deviceName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Current',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              deviceOs,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              lastActiveText,
              style: TextStyle(
                color: isDark
                    ? colorScheme.onSurface.withValues(alpha: 0.6)
                    : colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: isCurrent
            ? null
            : IconButton(
                icon: Icon(Icons.logout, color: colorScheme.error),
                tooltip: 'Log out device',
                onPressed: () async {
                  final user = _auth.currentUser;
                  if (user != null) {
                    await SessionService().logoutDevice(user.uid, doc.id);
                    if (mounted) {
                      showCustomSnackBar(context, 'Device logged out');
                    }
                  }
                },
              ),
      ),
    );
  }
}
