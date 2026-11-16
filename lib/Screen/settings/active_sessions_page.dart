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

typedef ActiveDevicesPage = ActiveSessionsPage;

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

  Future<void> _logoutAllOtherDevices(List<DocumentSnapshot> devices) async {
    final user = _auth.currentUser;
    if (user == null || _currentDeviceId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out of all other devices?'),
        content: const Text(
          'This will immediately disconnect your account from all other logged-in devices and sessions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionService().logoutAllOtherDevices(user.uid);
      if (mounted) {
        showCustomSnackBar(context, 'Logged out of all other devices');
      }
    }
  }

  Future<void> _logoutSingleDevice(String targetDeviceId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out this device?'),
        content: const Text(
          'This session will be remotely terminated immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionService().logoutDevice(user.uid, targetDeviceId);
      if (mounted) {
        showCustomSnackBar(context, 'Device logged out');
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
          'Active Devices',
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
                  .collection('devices')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No active devices found.'));
                }

                final devices = snapshot.data!.docs;
                final otherDevices = devices
                    .where((doc) => doc.id != _currentDeviceId)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'These are the devices currently logged into your account. You can log out of any unfamiliar devices.',
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (otherDevices.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton.icon(
                          onPressed: () => _logoutAllOtherDevices(devices),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.errorContainer,
                            foregroundColor: colorScheme.onErrorContainer,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.logout, size: 20),
                          label: const Text(
                            'Log out of all other devices',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    _buildSectionHeader('THIS DEVICE', colorScheme),
                    ...devices
                        .where((doc) => doc.id == _currentDeviceId)
                        .map(
                          (doc) => _buildDeviceTile(
                            doc,
                            isCurrent: true,
                            colorScheme: colorScheme,
                          ),
                        ),

                    if (otherDevices.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('OTHER DEVICES', colorScheme),
                      ...otherDevices.map(
                        (doc) => _buildDeviceTile(
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

  Widget _buildDeviceTile(
    DocumentSnapshot doc, {
    required bool isCurrent,
    required ColorScheme colorScheme,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final data = doc.data() as Map<String, dynamic>;
    final deviceModel =
        data['deviceModel'] ?? data['deviceName'] ?? 'Unknown Device';
    final deviceOs =
        data['deviceOs'] ?? data['osVersion'] ?? 'Unknown OS';
    final lastActive =
        (data['lastActive'] ?? data['loginTimestamp']) as Timestamp?;

    String lastActiveText = isCurrent ? 'Active now' : 'Recently active';
    if (lastActive != null && !isCurrent) {
      final date = lastActive.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 60) {
        lastActiveText = 'Active ${diff.inMinutes} mins ago';
      } else if (diff.inHours < 24) {
        lastActiveText = 'Active ${diff.inHours} hours ago';
      } else {
        lastActiveText = 'Last active: ${date.day}/${date.month}/${date.year}';
      }
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
                : deviceOs.toLowerCase().contains('windows')
                ? Icons.desktop_windows
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
                deviceModel,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'This device',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 11,
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
            : TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text(
                  'Log out',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => _logoutSingleDevice(doc.id),
              ),
      ),
    );
  }
}
