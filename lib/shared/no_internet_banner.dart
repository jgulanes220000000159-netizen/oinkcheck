import 'package:flutter/material.dart';
import 'connectivity_service.dart';

class NoInternetBanner extends StatefulWidget {
  final Widget child;
  final String? message;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double? topOffset;
  final bool forceShow; // For testing purposes

  const NoInternetBanner({
    Key? key,
    required this.child,
    this.message,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.topOffset,
    this.forceShow = false,
  }) : super(key: key);

  @override
  State<NoInternetBanner> createState() => _NoInternetBannerState();
}

class _NoInternetBannerState extends State<NoInternetBanner> {
  bool _isHidden = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connectivityService,
      builder: (context, _) {
        try {
          // Check if service is initialized before accessing it
          if (!connectivityService.isInitialized) {
            return widget
                .child; // Return child without banner if service not ready
          }

          print(
            '🌐 Banner build: isConnected = ${connectivityService.isConnected}',
          );

          // Reset hidden state when connection is restored
          if (connectivityService.isConnected && _isHidden) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isHidden = false;
                });
              }
            });
          }

          final shouldShow =
              (!connectivityService.isConnected || widget.forceShow) &&
              !_isHidden;
          return Stack(
            alignment: Alignment.topLeft,
            children: [
              widget.child,
              if (shouldShow)
                Positioned(
                  top: widget.topOffset ?? 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    elevation: 8,
                    color: Colors.transparent,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: widget.backgroundColor ?? Colors.red[600],
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.icon ?? Icons.wifi_off,
                              color: widget.textColor ?? Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.message ?? 'No Internet Connection',
                                style: TextStyle(
                                  color: widget.textColor ?? Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: widget.textColor ?? Colors.white,
                                size: 20,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _isHidden = true;
                                });
                              },
                              tooltip: '', // Disabled to prevent overlay error
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        } catch (e) {
          print('🌐 Error in banner build: $e');
          return widget
              .child; // Return child without banner if there's an error
        }
      },
    );
  }
}
