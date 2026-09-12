import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_commander/pirates/world/caribbean.dart';
import 'package:dot_commander/pirates/progression/fleet_progress.dart';
import 'package:dot_commander/ui/management/progression_panel.dart';

void main() {
  testWidgets(
    'Shop exposes eight explicit category choices and shows a reward',
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
      for (final c in ChestCategory.values) {
        for (final r in ChestKind.values) {
          expect(find.byKey(Key('chest_${c.name}_${r.name}')), findsOneWidget);
        }
      }
      final button = find.byKey(const Key('chest_cannon_rare'));
      await t.ensureVisible(button);
      await t.pump();
      await t.tap(button);
      await t.pump();
      expect(v.progress.inventory.single.kind, ItemKind.cannon);
      expect(v.gems, 50);
      expect(find.textContaining('Received Fine '), findsOneWidget);
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
