import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Flutter's web engine reports no view padding, so on an iPhone the tab bar would sit under the
/// home indicator and in the rounded corners. This reads the CSS safe-area insets (the page uses
/// viewport-fit=cover) and puts them into the MediaQuery, where SafeArea finds them.
class BrowserSafeArea extends StatefulWidget {
  final Widget child;
  const BrowserSafeArea({super.key, required this.child});

  @override
  State<BrowserSafeArea> createState() => _BrowserSafeAreaState();
}

class _BrowserSafeAreaState extends State<BrowserSafeArea> {
  late final web.HTMLDivElement _probe;
  late final JSFunction _onResize = ((web.Event _) => _measure()).toJS;
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    _coverViewport();
    _probe = web.HTMLDivElement()
      ..style.cssText =
          'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;pointer-events:none;'
          'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
    web.document.body!.append(_probe);
    web.window.addEventListener('resize', _onResize);
    _measure();
  }

  @override
  void dispose() {
    web.window.removeEventListener('resize', _onResize);
    _probe.remove();
    super.dispose();
  }

  /// The engine replaces the page's viewport tag with its own, without viewport-fit=cover; without
  /// it Safari keeps the page out of the status bar and home indicator areas and reports no insets.
  static void _coverViewport() {
    final meta = web.document.querySelector('meta[name=viewport]') as web.HTMLMetaElement?;
    if (meta != null && !meta.content.contains('viewport-fit')) meta.content = '${meta.content}, viewport-fit=cover';
  }

  void _measure() {
    final s = web.window.getComputedStyle(_probe);
    double px(String v) => double.tryParse(v.replaceAll('px', '')) ?? 0;
    final insets = EdgeInsets.fromLTRB(px(s.paddingLeft), px(s.paddingTop), px(s.paddingRight), px(s.paddingBottom));
    if (insets != _insets && mounted) setState(() => _insets = insets);
  }

  @override
  Widget build(BuildContext context) {
    if (_insets == EdgeInsets.zero) return widget.child;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        viewPadding: _insets,
        // The on-screen keyboard covers the bottom inset.
        padding: _insets.copyWith(bottom: mq.viewInsets.bottom > 0 ? 0 : _insets.bottom),
      ),
      child: widget.child,
    );
  }
}
