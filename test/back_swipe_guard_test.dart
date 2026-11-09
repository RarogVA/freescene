import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freescene/navigation/back_swipe_guard.dart';

void main() {
  testWidgets('horizontal regions use current scaled bounds and clean up', (
    tester,
  ) async {
    var overflowing = true;
    const content = ValueKey('horizontal-content');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: FittedBox(
              child: SizedBox(
                width: 200,
                height: 100,
                child: BackSwipeGuard(
                  enabled: () => overflowing,
                  child: const SizedBox.expand(key: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byKey(content));
    expect(bounds.size, const Size(400, 200));
    expect(BackSwipeGuard.blocks(bounds.center), isTrue);
    expect(BackSwipeGuard.blocks(bounds.topLeft - const Offset(1, 1)), isFalse);
    // Reading the controller extent through this callback needs no rebuild.
    overflowing = false;
    expect(BackSwipeGuard.blocks(bounds.center), isFalse);
    overflowing = true;
    expect(BackSwipeGuard.blocks(bounds.center), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(BackSwipeGuard.blocks(bounds.center), isFalse);
  });

  testWidgets('offstage content cannot block another screen', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Offstage(
          child: BackSwipeGuard(child: SizedBox(width: 200, height: 100)),
        ),
      ),
    );
    expect(BackSwipeGuard.blocks(const Offset(10, 10)), isFalse);
  });

  testWidgets('a scrolled table cannot block its clipped toolbar area', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const content = ValueKey('long-horizontal-table');
    const viewport = ValueKey('table-viewport');
    const toolbar = ValueKey('toolbar');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(key: toolbar, height: 60, width: 300),
                SizedBox(
                  key: viewport,
                  height: 200,
                  child: ListView(
                    controller: scroll,
                    padding: EdgeInsets.zero,
                    children: const [
                      BackSwipeGuard(
                        child: SizedBox(key: content, height: 1000),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(200);
    await tester.pump();
    final hiddenPoint = tester.getCenter(find.byKey(toolbar));
    final visiblePoint = tester.getCenter(find.byKey(viewport));
    final contentBounds = tester.getRect(find.byKey(content));
    expect(contentBounds.contains(hiddenPoint), isTrue);
    expect(contentBounds.contains(visiblePoint), isTrue);
    expect(BackSwipeGuard.blocks(hiddenPoint), isFalse);
    expect(BackSwipeGuard.blocks(visiblePoint), isTrue);
    expect(
      BackSwipeGuard.blocks(
        tester.getRect(find.byKey(viewport)).bottomCenter + const Offset(0, 20),
      ),
      isFalse,
    );
  });
}
