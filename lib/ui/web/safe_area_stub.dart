import 'package:flutter/widgets.dart';

/// Native platforms report their insets themselves.
class BrowserSafeArea extends StatelessWidget {
  final Widget child;
  const BrowserSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
