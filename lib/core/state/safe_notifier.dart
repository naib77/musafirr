import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Makes a [ChangeNotifier]'s notifications build-phase-safe and dispose-safe.
///
/// Two recurring hazards this removes, so callers never have to:
///
/// 1. **Notify during build.** Calling [notifyListeners] synchronously while
///    Flutter is in its build/layout/paint phase (e.g. from a `load()` /
///    `open()` / `initialize()` method invoked in a widget's `initState`)
///    triggers *"setState() or markNeedsBuild() called during build"*. This
///    mixin detects that phase and defers the notification to the next
///    post-frame instead of firing it mid-build.
///
/// 2. **Notify after dispose.** A deferred or late-async notification that
///    fires after the notifier is disposed throws. Once disposed, this mixin
///    drops notifications.
///
/// Usage — add the mixin, change nothing else:
/// ```dart
/// class FooState extends ChangeNotifier with SafeNotifier { ... }
/// ```
/// Existing `notifyListeners()` calls become safe automatically; there is no
/// need to wrap call sites in `addPostFrameCallback`.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // We're mid-frame (build/layout/paint). Notifying now would mark a
      // listening widget dirty during build. Defer to just after this frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) super.notifyListeners();
      });
    } else {
      super.notifyListeners();
    }
  }
}
