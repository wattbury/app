import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import 'safe_area_stub.dart' if (dart.library.js_interop) 'safe_area_web.dart';

/// Browser glue around the app: the safe-area insets Flutter's web engine does not report, and
/// the browser's theme colour (status bar, Safari toolbar) following the app's light or dark look.
class WebChrome extends StatelessWidget {
  final Widget child;
  const WebChrome({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    // The web engine turns the status bar colour into <meta name="theme-color">. Without this region
    // the framework sends a style without colour, which removes the tag again.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle(context.wb, Theme.of(context).brightness),
      child: BrowserSafeArea(child: child),
    );
  }
}
