import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/theme/app_palettes.dart';
import 'package:musafir/core/theme/app_theme.dart';

/// Proves the chip theme reaches a real chip.
///
/// `app_palettes_test` asserts the *colours* are far enough apart in every
/// palette; it cannot show that a chip on screen actually wears them. That gap
/// matters here because the selected label colour is a [WidgetStateColor], and
/// RawChip resolves only `labelStyle.color` against widget states — the rest of
/// the TextStyle it takes literally. If that resolution ever stops happening,
/// the palette test stays green while every selected chip loses its label.
///
/// The theme is built with [AppTheme.chipThemeFor] rather than
/// [AppTheme.forPalette] on purpose: the full theme resolves its text theme
/// through GoogleFonts, which in a test wants a font asset that is not bundled.
void main() {
  const p = AppPalettes.coralInk;

  /// The chip's fill, read where RawChip actually paints it: an [Ink] whose
  /// [ShapeDecoration] colour is tweened between `backgroundColor` and
  /// `selectedColor` by the selection animation. The enclosing [Material] has a
  /// null colour, so reading that instead reports nothing at all.
  ///
  /// Every caller pumps to settle first — mid-animation this is a blend of the
  /// two, which would make an exact-colour assertion flaky rather than wrong.
  Color? fillOf(WidgetTester tester, String label) {
    final ink = tester.widget<Ink>(
      find.ancestor(of: find.text(label), matching: find.byType(Ink)).first,
    );
    return (ink.decoration as ShapeDecoration?)?.color;
  }

  /// The label's effective colour after DefaultTextStyle and any merge.
  Color? labelColorOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.text(label)).text.style?.color;

  Future<void> pumpChips(WidgetTester tester) async {
    var selected = <String>{};
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(chipTheme: AppTheme.chipThemeFor(p)),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Wrap(
            children: [
              for (final name in ['Seat', 'Room'])
                FilterChip(
                  label: Text(name),
                  selected: selected.contains(name),
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    selected.contains(name)
                        ? selected.remove(name)
                        : selected.add(name);
                  }),
                ),
            ],
          ),
        ),
      ),
    ));
  }

  testWidgets('an unselected chip wears the muted fill and ink label',
      (tester) async {
    await pumpChips(tester);
    await tester.pumpAndSettle();
    expect(fillOf(tester, 'Room'), p.surfaceMuted);
    expect(labelColorOf(tester, 'Room'), p.ink);
  });

  // The reported bug, at the widget level: tapping a type chip did change the
  // state, but nothing on screen moved, so the control read as broken.
  testWidgets('tapping a chip visibly selects it', (tester) async {
    await pumpChips(tester);
    final before = fillOf(tester, 'Room');

    await tester.tap(find.text('Room'));
    await tester.pumpAndSettle();

    expect(fillOf(tester, 'Room'), p.brand,
        reason: 'a tapped chip should be filled with the brand');
    expect(fillOf(tester, 'Room'), isNot(before),
        reason: 'the fill did not change at all — this is the reported bug');
    // The WidgetStateColor resolved. If RawChip ever stops resolving it this
    // reads as p.ink, i.e. #222222 on a #222222 fill.
    expect(labelColorOf(tester, 'Room'), p.surface,
        reason: 'the selected label must flip off the dark fill');
  });

  testWidgets('selecting one chip leaves its neighbour alone', (tester) async {
    await pumpChips(tester);
    await tester.tap(find.text('Room'));
    await tester.pumpAndSettle();
    expect(fillOf(tester, 'Room'), p.brand);
    expect(fillOf(tester, 'Seat'), p.surfaceMuted);
  });

  // The search type row builds its label as `Text(label, style:
  // TextStyle(fontSize: 12))`. That style has `inherit: true`, so it overrides
  // only the size and takes its colour from the DefaultTextStyle the chip sets
  // — but it is the exact shape of the reported control, so it is worth pinning
  // that an explicit style on the Text does not strand the label at ink.
  testWidgets('a label carrying its own size still flips colour',
      (tester) async {
    var selected = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(chipTheme: AppTheme.chipThemeFor(p)),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: FilterChip(
            label: const Text('Full House', style: TextStyle(fontSize: 12)),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => setState(() => selected = !selected),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(labelColorOf(tester, 'Full House'), p.ink);

    await tester.tap(find.text('Full House'));
    await tester.pumpAndSettle();
    expect(fillOf(tester, 'Full House'), p.brand);
    expect(labelColorOf(tester, 'Full House'), p.surface);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Full House'))
          .text
          .style
          ?.fontSize,
      12,
      reason: 'the call site\'s own font size must survive the theme',
    );
  });

  testWidgets('a chip can be deselected again', (tester) async {
    await pumpChips(tester);
    await tester.tap(find.text('Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room'));
    await tester.pumpAndSettle();
    expect(fillOf(tester, 'Room'), p.surfaceMuted);
    expect(labelColorOf(tester, 'Room'), p.ink);
  });
}
