import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/ui/management/progression_panel.dart';

void main() {
  testWidgets(
    'Shop exposes six explicit category choices and shows a reward',
    (t) async {
      final v = createCaribbean()..gems = 100;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgressionPanel(
                voyage: v,
                ship: v.ships.first,
                tab: 0,
                changed: () {},
              ),
            ),
          ),
        ),
      );
      // Shop cleanup pass 2026-09-22: ChestCategory.equipment's two rows
      // (the plain "Common/Rare Equipment Chest" gem purchases) were
      // removed as redundant with ChestCategory.hull's own wider family
      // -- see progression_panel.dart's own doc comment. The remaining
      // three categories (hull, crew, officers) still get a row each.
      for (final c in ChestCategory.values) {
        for (final r in ChestKind.values) {
          final finder = find.byKey(Key('chest_${c.name}_${r.name}'));
          if (c == ChestCategory.equipment) {
            expect(finder, findsNothing);
          } else {
            expect(finder, findsOneWidget);
          }
        }
      }
      // Ship/combat overhaul pass 2026-09-21: ChestCategory.cannon
      // ("Ordnance") is removed -- it was the only category whose pool
      // was a single guaranteed ItemKind (cannon shot types), which is
      // what let this test assert a specific resulting kind without
      // seeding the roll. No remaining category offers that guarantee
      // (every one now covers multiple ItemKinds), so this checks the
      // general reward flow -- a tap grants SOME item from the tapped
      // category's own pool, spends the right gems, and shows the
      // reward -- instead of one specific kind.
      final button = find.byKey(const Key('chest_officers_rare'));
      await t.ensureVisible(button);
      await t.pump();
      await t.tap(button);
      await t.pump();
      expect(ChestCategory.officers.accepts(v.progress.inventory.single.kind), isTrue);
      expect(v.gems, 50);
      expect(find.textContaining('Received '), findsOneWidget);
    },
  );
  testWidgets(
    'Tree shows current earned offline cap, not the maximum for everyone',
    (t) async {
      final v = createCaribbean();
      Future<void> show() async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProgressionPanel(
                  voyage: v,
                  ship: v.ships.first,
                  tab: 1,
                  changed: () {},
                ),
              ),
            ),
          ),
        );
      }

      await show();
      expect(find.textContaining('Current cap: 4h 0m'), findsOneWidget);
      v.progress.tree[FleetTrack.offline] = 500;
      await show();
      expect(find.textContaining('Current cap: 6h 0m'), findsOneWidget);
    },
  );
}
