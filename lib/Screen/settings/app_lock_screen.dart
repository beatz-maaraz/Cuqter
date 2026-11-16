import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart' as huge;
import 'package:cuqter/services/biometric_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  bool _isAuthenticating = false;
  String _errorMessage = '';
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _checkPinAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _checkPinAvailability() async {
    final hasPin = await BiometricService.isTwoStepVerificationEnabled();
    if (mounted) {
      setState(() => _hasPin = hasPin);
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    if (mounted) {
      setState(() {
        _isAuthenticating = true;
        _errorMessage = '';
      });
    }

    final bool authenticated = await BiometricService.authenticate(
      reason: 'Unlock Cuqter',
    );

    if (mounted) {
      if (authenticated) {
        widget.onUnlocked();
      } else {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = 'Authentication failed. Please try again.';
        });
      }
    }
  }

  void _showPinUnlockDialog() {
    final pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  huge.HugeIcon(
                    icon: huge.HugeIcons.strokeRoundedLockPassword,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text('Enter Security PIN'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your 6-digit Security PIN to unlock the app.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      errorText: pinError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final enteredPin = pinController.text.trim();
                    if (enteredPin.length != 6) {
                      setDialogState(() {
                        pinError = 'PIN must be 6 digits';
                      });
                      return;
                    }
                    final isValid =
                        await BiometricService.verifySecurityPin(enteredPin);
                    if (isValid) {
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      widget.onUnlocked();
                    } else {
                      setDialogState(() {
                        pinError = 'Incorrect PIN. Please try again.';
                      });
                    }
                  },
                  child: const Text('Unlock'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // Prevent back button bypassing lock screen
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),

                // Logo or Lock Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: huge.HugeIcon(
                    icon: huge.HugeIcons.strokeRoundedSecurityValidation,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'Cuqter Locked',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Use your fingerprint, Face ID, or Security PIN to unlock your application.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),

                if (_errorMessage.isNotEmpty) ...[
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const Spacer(),

                // Unlock with Biometrics Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: _isAuthenticating ? null : _authenticate,
                    icon: _isAuthenticating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : huge.HugeIcon(
                            icon:
                                huge.HugeIcons.strokeRoundedSecurityValidation,
                            size: 24,
                            color: colorScheme.onPrimary,
                          ),
                    label: Text(
                      _isAuthenticating ? 'Authenticating...' : 'Unlock Now',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (_hasPin) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _showPinUnlockDialog,
                    icon: huge.HugeIcon(
                      icon: huge.HugeIcons.strokeRoundedLockPassword,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    label: Text(
                      'Unlock with Security PIN',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
