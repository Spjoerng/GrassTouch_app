import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_app/src/ui/journal_motion.dart';

void main() {
  for (final media in [
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets('Entrance respects accessibility settings $media', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: media,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: JournalReveal(child: Text('Journal')),
          ),
        ),
      );
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition))
            .opacity
            .value,
        1,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  }

  testWidgets('Entrance settles and does not replay on rebuild', (
    tester,
  ) async {
    Widget content(String text) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: JournalReveal(child: Text(text)),
      ),
    );
    await tester.pumpWidget(content('First'));
    expect(
      tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value,
      0,
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(content('Updated'));
    expect(
      tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value,
      1,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
