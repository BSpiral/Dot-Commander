import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/simulation/vessel.dart';
import '../pirates/persistence/voyage_store.dart';
import '../pirates/world/caribbean.dart';
import '../pirates/visuals/pirates_game.dart';
import 'management/management_panel.dart';

class CommandScreen extends StatefulWidget {
  final VoyageStore? store;
  const CommandScreen({super.key, this.store});
  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen>
    with WidgetsBindingObserver {
  var simulation = createCaribbean();
  late final store = widget.store ?? VoyageStore();
  bool ready = false, canSave = false, paused = false;
  int tab = 3;
  int savedRevision = 0;
  String? shownBattle;
  String? saveError;
  Timer? saveTimer, timer;
  final _gameKey = GlobalKey();
  late Vessel selected = simulation.ships.firstWhere((s) => s.playerOwned);
  late final PiratesGame game = PiratesGame(
    simulation,
    (ship) => setState(() => selected = ship),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && ready) {
        final run = simulation.encounterFor(selected.id);
        if (run != null &&
            simulation.busy(selected.id) &&
            run.result.id != shownBattle) {
          shownBattle = run.result.id;
          tab = 3;
        }
        if (simulation.revision != savedRevision) {
          savedRevision = simulation.revision;
          _save();
        }
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    _save();
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loaded = await store.load();
      if (!mounted) return;
      simulation = loaded;
      canSave = true;
    } catch (_) {
      saveError =
          'Could not load voyage. Original save preserved; autosave paused.';
    }
    if (!mounted) return;
    selected = simulation.ships.firstWhere((s) => s.playerOwned);
    game.selectedId = selected.id;
    setState(() => ready = true);
    saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  Future<void> _save() async {
    if (!ready || !canSave) return;
    try {
      await store.save(simulation);
      if (mounted && saveError != null) setState(() => saveError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError = 'Could not save voyage. Will retry automatically.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ready) return;
    if (state == AppLifecycleState.resumed && !paused) {
      game.resumeEngine();
    } else {
      game.pauseEngine();
      _save();
    }
  }

  Future<void> _debugReset() async {
    if (!kDebugMode || !ready) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DEBUG: Reset entire voyage?'),
        content: const Text(
          'Erase all commands, names/orders, Tree levels, equipment, chests/rewards, coins/gems, cargo, battles, logs and world state. Start a fresh one-ship voyage. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm_debug_reset'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final couldSave = canSave;
    game.pauseEngine();
    setState(() {
      ready = false;
      canSave = false;
    });
    try {
      // Save uses the existing ordered queue: prior autosaves finish first.
      // Disable this screen's autosaves, including disposal, before replacing it.
      await store.save(createCaribbean(encountersEnabled: true));
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => CommandScreen(store: store)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        ready = true;
        canSave = couldSave;
        saveError = 'Debug reset failed; current voyage retained.';
      });
      if (!paused) game.resumeEngine();
    }
  }

  void _select(Vessel ship) {
    setState(() => selected = ship);
    game.locate(ship);
  }

  void _order(BehaviorMode mode) {
    if (!selected.playerOwned) return;
    setState(() => simulation.setBehavior(selected, mode));
    _save();
  }

  Widget _fleet(List<Vessel> fleet) => SizedBox(
    height: 54,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Tooltip(
                    message: i < fleet.length
                        ? fleet[i].name
                        : 'Purchase another command in Shop',
                    child: OutlinedButton(
                      key: Key('fleet_slot_$i'),
                      onPressed: i < fleet.length
                          ? () => _select(fleet[i])
                          : () => setState(() => tab = 0),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        minimumSize: const Size(0, 48),
                        backgroundColor:
                            i < fleet.length && selected.id == fleet[i].id
                            ? const Color(0xff365057)
                            : null,
                        side: BorderSide(
                          color: i < fleet.length && selected.id == fleet[i].id
                              ? const Color(0xffe8c786)
                              : Colors.white12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (i < fleet.length)
                            Icon(
                              fleet[i].activity == Activity.engaged
                                  ? Icons.shield_outlined
                                  : fleet[i].activity == Activity.docked
                                  ? Icons.anchor
                                  : Icons.sailing_outlined,
                              size: 13,
                            ),
                          Text(
                            'Ship ${i + 1}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget _orders(bool wide, {bool horizontal = false}) {
    const modes = [
      BehaviorMode.explorer,
      BehaviorMode.merchant,
      BehaviorMode.pirate,
      BehaviorMode.privateer,
    ];
    const icons = [
      Icons.explore_outlined,
      Icons.local_shipping_outlined,
      Icons.flag_outlined,
      Icons.shield_outlined,
    ];
    return SizedBox(
      width: horizontal ? 208 : (wide ? 125 : 48),
      child: Flex(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < modes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Tooltip(
                message:
                    '${modes[i].name}${selected.playerOwned ? '' : ' (NPC)'}',
                child: Semantics(
                  selected: selected.behavior == modes[i],
                  child: TextButton(
                    key: Key('order_${modes[i].name}'),
                    onPressed: selected.playerOwned
                        ? () => _order(modes[i])
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: Size(wide ? 120 : 48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: selected.behavior == modes[i]
                          ? const Color(0xff526053)
                          : const Color(0xff163845),
                      foregroundColor: selected.behavior == modes[i]
                          ? const Color(0xffffdc93)
                          : Colors.white70,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i], size: 21),
                        if (wide) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              modes[i].name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _map(bool wide) => Container(
    key: const Key('living_map'),
    color: const Color(0xff092b3b),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${selected.behavior.name} • ${selected.name} • ${paused
                      ? 'paused'
                      : selected.recovering
                      ? 'recovery tow'
                      : selected.activity.name} → ${selected.destination?.name ?? 'Setting sail'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffe3cf9b),
                  ),
                ),
              ),
              Text(
                '${simulation.ships.where((s) => s.atSea).length} sails',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: wide ? 0 : 60,
                      child: GameWidget(key: _gameKey, game: game),
                    ),
                    if (!wide)
                      Positioned(
                        right: 4,
                        bottom: 8,
                        child: _orders(false, horizontal: true),
                      ),
                    if (kDebugMode)
                      Positioned(
                        left: 8,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Text(
                            '${game.fps.toStringAsFixed(0)} FPS • ${selected.load.name} • pace ${selected.effectiveSpeed.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _orders(wide),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _management(int fleetSize) => Container(
    key: const Key('management_area'),
    decoration: const BoxDecoration(
      color: Color(0xff132c36),
      border: Border(top: BorderSide(color: Color(0xffa58e61))),
    ),
    child: Column(
      children: [
        if (saveError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              saveError!,
              maxLines: 2,
              style: const TextStyle(color: Colors.amber, fontSize: 11),
            ),
          ),
        SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Semantics(
                    selected: tab == i,
                    child: InkWell(
                      key: Key('tab_${managementLabels[i].toLowerCase()}'),
                      onTap: () => setState(() => tab = i),
                      child: Container(
                        color: tab == i ? const Color(0xff374c4c) : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              [
                                Icons.storefront_outlined,
                                Icons.account_tree_outlined,
                                Icons.build_outlined,
                                Icons.sailing_outlined,
                                Icons.settings_outlined,
                              ][i],
                              size: 20,
                              color: tab == i
                                  ? const Color(0xffffd78b)
                                  : Colors.white54,
                            ),
                            Text(
                              managementLabels[i],
                              style: TextStyle(
                                fontSize: 11,
                                color: tab == i
                                    ? const Color(0xffffd78b)
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ManagementPanel(
            voyage: simulation,
            debugReset: kDebugMode ? _debugReset : null,
            onChanged: () {
              setState(() {});
              _save();
            },
            encounter: simulation.encounterFor(selected.id),
            dismissEncounter: () {
              setState(() => simulation.dismissResult());
              _save();
            },
            soundEnabled: simulation.soundEnabled,
            toggleSound: () {
              setState(
                () => simulation.soundEnabled = !simulation.soundEnabled,
              );
              _save();
            },
            tab: tab,
            ship: selected,
            fleetSize: fleetSize,
            saveError: saveError,
            paused: paused,
            togglePause: () => setState(() {
              paused = !paused;
              if (paused) {
                game.pauseEngine();
              } else {
                game.resumeEngine();
              }
            }),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 40,
      title: const Text(
        'Dot Commander: Pirates',
        style: TextStyle(fontSize: 18),
      ),
    ),
    body: !ready
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide =
                    MediaQuery.orientationOf(context) ==
                        Orientation.landscape &&
                    c.maxWidth > c.maxHeight;
                final fleet = simulation.ships
                    .where((s) => s.playerOwned)
                    .toList();
                return Column(
                  children: [
                    _fleet(fleet),
                    SizedBox(
                      height: 26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '● ${simulation.coins} coins',
                                key: const Key('coins'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xffffd58a),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '◆ ${simulation.gems} gems',
                                key: const Key('gems'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xff9cddda),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (selected.activity == Activity.engaged)
                              const Tooltip(
                                message: 'In battle',
                                child: Icon(
                                  Icons.shield_outlined,
                                  key: Key('battle_status'),
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: wide
                          ? Row(
                              children: [
                                Expanded(child: _map(c.maxWidth >= 900)),
                                SizedBox(
                                  width: c.maxWidth >= 900
                                      ? 360
                                      : c.maxWidth * .43,
                                  child: _management(fleet.length),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(child: _map(false)),
                                SizedBox(
                                  height: ((c.maxHeight - 80) * .38).clamp(
                                    170.0,
                                    370.0,
                                  ),
                                  child: _management(fleet.length),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
  );
}
