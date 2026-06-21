import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/state/safe_notifier.dart';

class _CounterNotifier extends ChangeNotifier with SafeNotifier {
  int value = 0;
  void bump() {
    value++;
    notifyListeners();
  }
}

void main() {
  testWidgets('defers notifyListeners called during build (no exception)',
      (tester) async {
    final notifier = _CounterNotifier();
    var bumpedDuringBuild = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: notifier,
          builder: (context, _) {
            // Notify WHILE building a widget that listens to this notifier.
            // A raw ChangeNotifier throws "markNeedsBuild during build" here;
            // SafeNotifier defers it to post-frame. Guarded so it fires once
            // (the deferred notify rebuilds, which must not re-bump).
            if (!bumpedDuringBuild) {
              bumpedDuringBuild = true;
              notifier.bump();
            }
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump(); // let the deferred post-frame notification run

    expect(tester.takeException(), isNull);
    expect(notifier.value, 1);

    notifier.dispose();
  });

  testWidgets('notifies synchronously when not in build phase',
      (tester) async {
    // Bind so SchedulerBinding.instance is available.
    await tester.pumpWidget(const SizedBox());

    final notifier = _CounterNotifier();
    var notifications = 0;
    notifier.addListener(() => notifications++);

    notifier.bump(); // outside build phase → fires immediately
    expect(notifications, 1);

    notifier.dispose();
  });

  testWidgets('drops notifications after dispose', (tester) async {
    final notifier = _CounterNotifier();
    notifier.dispose();

    // Raw ChangeNotifier asserts when notified after dispose; SafeNotifier
    // returns early.
    expect(notifier.bump, returnsNormally);
  });
}
