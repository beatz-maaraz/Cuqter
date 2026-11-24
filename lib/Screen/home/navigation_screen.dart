import 'package:cuqter/utils/colors.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cuqter/Screen/profile/profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cuqter/services/update_service.dart';
import 'package:cuqter/services/notification_service.dart';
import 'package:cuqter/widgets/update_dialog.dart';
import 'package:cuqter/Screen/calls/calls_history_page.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cuqter/Screen/home/homepage.dart';
import 'package:cuqter/Screen/calls/incoming_call_screen.dart';
import 'package:hugeicons/hugeicons.dart' as huge;
import 'package:cuqter/services/web_lifecycle.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  int _selectedIndex = 0;
  late PageController _pageController;
  bool _isProgrammaticChange = false;
  late final AppLifecycleListener _lifecycleListener;
  StreamSubscription<DatabaseEvent>? _incomingCallSubscription;
  String? _currentRingingRoomId;
  bool _isShowingIncomingCall = false;

  Stream<DocumentSnapshot>? _currentUserStream;

  List<Widget> get _screens => [
    const Homepage(),
    CallsHistoryPage(isActive: _selectedIndex == 1),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);

    // Initialize push notification service
    NotificationService().initialize();

    // Check for updates after the first frame so context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());

    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onStateChanged,
      onExitRequested: () async {
        await _setUserStatus(false);
        return AppExitResponse.exit;
      },
    );

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _currentUserStream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots();
      setupWebLifecycle(currentUser.uid);
      _listenForIncomingCalls(currentUser.uid);
    }

    _setUserStatus(true);
  }

  void _listenForIncomingCalls(String uid) {
    _incomingCallSubscription = FirebaseDatabase.instance
        .ref('incoming_calls/$uid')
        .onValue
        .listen((event) {
          if (event.snapshot.value != null) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            final roomId = data['roomId'] as String?;
            final callerName = data['callerName'] as String? ?? 'Unknown';
            final callerId = data['callerId'] as String? ?? '';
            final callerPic = data['callerPic'] as String?;
            final isVideoCall = data['isVideo'] as bool? ?? false;

            // Guard: skip if this room is already being shown or ringing
            if (_isShowingIncomingCall && _currentRingingRoomId == roomId) {
              return;
            }

            _currentRingingRoomId = roomId;
            _isShowingIncomingCall = true;

            NotificationService.showIncomingCallNotification(
              callerName: callerName,
              roomId: roomId ?? '',
              callerId: callerId,
              isVideoCall: isVideoCall,
              callerPic: callerPic,
            );

            // On Web, CallKit is not supported, so push Flutter IncomingCallScreen.
            // On mobile (Android/iOS), Android Full-Screen Intent and iOS CallKit manage the incoming call UI without duplication.
            if (kIsWeb && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => IncomingCallScreen(
                    roomId: roomId ?? '',
                    callerName: callerName,
                    callerId: callerId,
                    isVideoCall: isVideoCall,
                  ),
                ),
              ).whenComplete(() {
                // Reset flag once the incoming call screen is dismissed
                _isShowingIncomingCall = false;
                if (_currentRingingRoomId == roomId) {
                  _currentRingingRoomId = null;
                }
              });
            }
          } else {
            _isShowingIncomingCall = false;
            if (_currentRingingRoomId != null) {
              NotificationService.cancelCallNotification(
                _currentRingingRoomId!,
              );
              _currentRingingRoomId = null;
            }
          }
        });
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && mounted) {
      await UpdateDialog.show(context, info);
    }
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    _lifecycleListener.dispose();
    _setUserStatus(false);
    _pageController.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setUserStatus(true);
    } else {
      _setUserStatus(false);
    }
  }

  Future<void> _setUserStatus(bool isOnline) async {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    if (auth.currentUser != null) {
      await firestore
          .collection('users')
          .doc(auth.currentUser!.uid)
          .update({
            'isOnline': isOnline,
            'lastSeen': FieldValue.serverTimestamp(),
          })
          .catchError((e) {
            // Handle error conceptually
          });
    }
  }

  void _onTabSelected(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      _isProgrammaticChange = true;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildNavItem(
    int index,
    String label,
    dynamic icon,
    dynamic activeIcon,
  ) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final unselectedColor = isDark
        ? AppColors.textSecondary
        : const Color(0xFF4B5563);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabSelected(index),
          borderRadius: BorderRadius.circular(25),
          splashColor: colorScheme.primary.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? AppColors.interactiveContainer : colorScheme.primary.withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: huge.HugeIcon(
                    icon: isSelected ? activeIcon : icon,
                    color: isSelected
                        ? (isDark ? AppColors.textPrimary : colorScheme.primary)
                        : unselectedColor,
                    size: 19,
                  ),
                ),
                const SizedBox(height: 1),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (isDark ? AppColors.textPrimary : colorScheme.primary)
                        : unselectedColor,
                    letterSpacing: 0.3,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileItem(int index) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final unselectedColor = isDark
        ? AppColors.textSecondary
        : const Color(0xFF4B5563);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabSelected(index),
          borderRadius: BorderRadius.circular(25),
          splashColor: colorScheme.primary.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? AppColors.interactiveContainer : colorScheme.primary.withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: _currentUserStream,
                  builder: (context, snapshot) {
                    String profilePic = '';
                    if (snapshot.hasData && snapshot.data!.exists) {
                      var data = snapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null) profilePic = data['profilepic'] ?? '';
                    }
                    return AnimatedScale(
                      scale: isSelected ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: Container(
                        padding: EdgeInsets.all(isSelected ? 1.5 : 0),
                        decoration: isSelected
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? AppColors.interactiveFocus : colorScheme.primary,
                                  width: 1.5,
                                ),
                              )
                            : null,
                        child: CircleAvatar(
                          radius: 9.5,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          backgroundImage: profilePic.isNotEmpty
                              ? (profilePic.startsWith('http')
                                    ? ResizeImage(
                                        CachedNetworkImageProvider(profilePic),
                                        width: 120,
                                        height: 120,
                                      )
                                    : AssetImage(profilePic) as ImageProvider)
                              : null,
                                              child: !(profilePic.isNotEmpty) ? const Icon(Icons.person, color: Colors.grey, size: 14) : null,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 1),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? (isDark ? AppColors.textPrimary : colorScheme.primary)
                        : unselectedColor,
                    letterSpacing: 0.3,
                  ),
                  child: const Text('PROFILE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(
    bool isSelected,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final unselectedColor = isDark
        ? AppColors.textSecondary
        : const Color(0xFF4B5563);

    return StreamBuilder<DocumentSnapshot>(
      stream: _currentUserStream,
      builder: (context, snapshot) {
        String profilePic = '';
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) profilePic = data['profilepic'] ?? '';
        }
        return Container(
          padding: EdgeInsets.all(isSelected ? 1.5 : 0),
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? AppColors.interactiveFocus
                        : colorScheme.primary,
                    width: 1.5,
                  ),
                )
              : null,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
            backgroundImage: profilePic.isNotEmpty
                ? (profilePic.startsWith('http')
                    ? ResizeImage(
                        CachedNetworkImageProvider(profilePic),
                        width: 120,
                        height: 120,
                      )
                    : AssetImage(profilePic) as ImageProvider)
                : null,
            child: profilePic.isEmpty
                ? Icon(Icons.person, color: unselectedColor, size: 14)
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide screen / desktop / tablet layout: Replace full-screen navigation with Row
        if (constraints.maxWidth >= 640) {
          return Scaffold(
            backgroundColor: isDark ? AppColors.baseScreen : colorScheme.surface,
            body: Row(
              children: [
                // Navigation rail on the left
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onTabSelected,
                  backgroundColor: isDark
                      ? AppColors.persistentBar
                      : const Color(0xFFF3F4F6),
                  indicatorColor: isDark
                      ? AppColors.interactiveContainer
                      : colorScheme.primary.withValues(alpha: 0.12),
                  labelType: NavigationRailLabelType.all,
                  minWidth: 72,
                  selectedIconTheme: IconThemeData(
                    color: isDark ? AppColors.textPrimary : colorScheme.primary,
                    size: 22,
                  ),
                  unselectedIconTheme: IconThemeData(
                    color: isDark
                        ? AppColors.textSecondary
                        : const Color(0xFF4B5563),
                    size: 22,
                  ),
                  selectedLabelTextStyle: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimary : colorScheme.primary,
                    letterSpacing: 0.3,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textSecondary
                        : const Color(0xFF4B5563),
                    letterSpacing: 0.3,
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: huge.HugeIcon(
                        icon: huge.HugeIcons.strokeRoundedChat01,
                        color: isDark
                            ? AppColors.textSecondary
                            : const Color(0xFF4B5563),
                        size: 22,
                      ),
                      selectedIcon: huge.HugeIcon(
                        icon: huge.HugeIcons.strokeRoundedBubbleChat,
                        color: isDark
                            ? AppColors.textPrimary
                            : colorScheme.primary,
                        size: 22,
                      ),
                      label: const Text('CHATS'),
                    ),
                    NavigationRailDestination(
                      icon: huge.HugeIcon(
                        icon: huge.HugeIcons.strokeRoundedCall,
                        color: isDark
                            ? AppColors.textSecondary
                            : const Color(0xFF4B5563),
                        size: 22,
                      ),
                      selectedIcon: huge.HugeIcon(
                        icon: huge.HugeIcons.strokeRoundedCalling,
                        color: isDark
                            ? AppColors.textPrimary
                            : colorScheme.primary,
                        size: 22,
                      ),
                      label: const Text('CALLS'),
                    ),
                    NavigationRailDestination(
                      icon: _buildProfileAvatar(false, isDark, colorScheme),
                      selectedIcon: _buildProfileAvatar(true, isDark, colorScheme),
                      label: const Text('PROFILE'),
                    ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDark
                      ? AppColors.divider
                      : const Color(0xFFE5E7EB),
                ),
                // Expanded widget on the right to display active screen content dynamically
                Expanded(
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
          );
        }

        // Mobile compact layout: Full-screen PageView with bottom navigation bar
        return Scaffold(
          extendBody: true,
          body: PageView(
            controller: _pageController,
            physics: kIsWeb
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            onPageChanged: (index) {
              if (_isProgrammaticChange) {
                if (index == _selectedIndex) {
                  setState(() => _isProgrammaticChange = false);
                }
                return;
              }
              if (_selectedIndex != index) {
                setState(() => _selectedIndex = index);
              }
            },
            children: _screens,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 80,
                right: 80,
                bottom: 15,
                top: 8,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: kIsWeb
                    ? Container(
                        height: 62,
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.persistentBar
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: isDark
                                ? AppColors.divider
                                : const Color(0xFFE5E7EB),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.3 : 0.08,
                              ),
                              blurRadius: 16,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildNavItem(
                              0,
                              'CHATS',
                              huge.HugeIcons.strokeRoundedChat01,
                              huge.HugeIcons.strokeRoundedBubbleChat,
                            ),
                            _buildNavItem(
                              1,
                              'CALLS',
                              huge.HugeIcons.strokeRoundedCall,
                              huge.HugeIcons.strokeRoundedCalling,
                            ),
                            _buildProfileItem(2),
                          ],
                        ),
                      )
                    : BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          height: 62,
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.persistentBar.withValues(alpha: 0.92)
                                : const Color(0xFFF3F4F6).withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.divider
                                  : const Color(0xFFE5E7EB),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.3 : 0.08,
                                ),
                                blurRadius: 16,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _buildNavItem(
                                0,
                                'CHATS',
                                huge.HugeIcons.strokeRoundedChat01,
                                huge.HugeIcons.strokeRoundedBubbleChat,
                              ),
                              _buildNavItem(
                                1,
                                'CALLS',
                                huge.HugeIcons.strokeRoundedCall,
                                huge.HugeIcons.strokeRoundedCalling,
                              ),
                              _buildProfileItem(2),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
