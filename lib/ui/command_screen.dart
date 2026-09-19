import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/simulation/vessel.dart';
import '../monetization/ads_service.dart';
import '../monetization/banner_ad_bar.dart';
import '../monetization/billing_service.dart';
import '../monetization/monetization_ids.dart';
import '../monetization/monetization_store.dart';
import '../monetization/rewarded_chest_service.dart';
import '../monetization/rewarded_gold_service.dart';
import '../pirates/persistence/voyage_store.dart';
import '../pirates/progression/fleet_progress.dart';
import '../pirates/world/caribbean.dart';
import '../pirates/visuals/pirates_game.dart';
import 'management/management_panel.dart';

class CommandScreen extends StatefulWidget {
  final VoyageStore? store;
  // Injectable clock, tests-only (defaults to real DateTime.now) --
  // lets the background/resume offline-reward path (see
  // didChangeAppLifecycleState) be driven deterministically instead of
  // depending on real wall-clock time actually elapsing during a test.
  final DateTime Function()? now;
  const CommandScreen({super.key, this.store, this.now});
  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen>
    with WidgetsBindingObserver {
  var simulation = createCaribbean();
  late final store = widget.store ?? VoyageStore();
  late final _now = widget.now ?? DateTime.now;
  late final monetizationStore = MonetizationStore();
  // One controller per real rewarded ad unit (three units currently back
  // five chest categories -- see MonetizationIds.rewardedAdUnitIdFor).
  // Sharing a controller across categories only shares ad supply; each
  // category's own daily allowance still lives independently in
  // MonetizationStore, keyed by category.
  late final rewardedAdControllers = {
    for (final group in RewardedAdGroup.values)
      group: RewardedAdController(
        adUnitId: MonetizationIds.rewardedAdUnitIdFor(group),
      ),
  };
  late final rewardedChestService = RewardedChestService(
    adsByGroup: {
      for (final group in RewardedAdGroup.values)
        group: rewardedAdControllers[group]!,
    },
    store: monetizationStore,
  );
  // Reuses the crewEquipment ad unit -- the freed reward opportunity from
  // consolidating 5 Common Chest ad rows down to 3 (see
  // RewardedChestTile/RewardedAdGroup) is presented as this distinct,
  // non-chest reward rather than a redundant 4th/5th chest path.
  late final rewardedGoldService = RewardedGoldService(
    ads: rewardedAdControllers[RewardedAdGroup.crewEquipment]!,
    store: monetizationStore,
  );
  late final billingService = BillingService(store: monetizationStore);
  bool ready = false, canSave = false, paused = false, hasRemoveAds = false;
  // Set when the app is backgrounded (pauseEngine), cleared on resume.
  // Lets a genuine background->foreground resume grant the SAME offline
  // reward a true cold start already does via VoyageStore.load -- see
  // didChangeAppLifecycleState. null means "not currently backgrounded"
  // (e.g. right after a cold start, where VoyageStore.load already
  // handled the offline gap for the time before this screen existed).
  DateTime? _backgroundedAt;
  // Whether the small Behavior tag's floating overlay/dropdown is open.
  // See _behaviorTag/_behaviorOptions/_openBehaviorMenu -- a real
  // Flutter Overlay entry anchored to the tag via a LayerLink, so it
  // paints (and is hit-testable) above the WHOLE screen rather than
  // being confined to the map's own Stack. That matters because the
  // popup's content can be taller than the map area on short screens
  // (small phones, short landscape) -- a Positioned overlay nested
  // inside the map's Stack is hit-testable only within that Stack's own
  // laid-out bounds (Clip.none affects painting, not hit-testing), so
  // an overflowing popup would render correctly but silently fail to
  // receive taps on its clipped-outside portion. A real Overlay has no
  // such bound.
  bool _behaviorMenuOpen = false;
  final LayerLink _behaviorLink = LayerLink();
  OverlayEntry? _behaviorOverlayEntry;
  int tab = 3;
  int savedRevision = 0;
  String? shownBattle;
  String? saveError;
  Timer? saveTimer, timer;
  StreamSubscription<bool>? _entitlementSub;
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
    _loadMonetization();
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
    _behaviorOverlayEntry?.remove();
    WidgetsBinding.instance.removeObserver(this);
    saveTimer?.cancel();
    _save();
    timer?.cancel();
    _entitlementSub?.cancel();
    billingService.dispose();
    super.dispose();
  }

  Future<void> _loadMonetization() async {
    final owned = await monetizationStore.hasRemoveAds();
    if (mounted) setState(() => hasRemoveAds = owned);
    for (final controller in rewardedAdControllers.values) {
      unawaited(controller.preload());
    }
    unawaited(billingService.start());
    _entitlementSub = billingService.entitlementGranted.listen((_) {
      if (mounted) setState(() => hasRemoveAds = true);
    });
  }

  /// Grants a free Common Chest roll earned by watching a rewarded ad.
  /// Called only via RewardedChestTile, which only calls this after
  /// RewardedChestService.watch has already reported
  /// RewardedChestOutcome.granted -- meaning the SDK confirmed the
  /// reward AND today's per-category allowance was atomically consumed
  /// in MonetizationStore. There is no await between that confirmation
  /// and this method's synchronous roll, so this is the single point
  /// where the reward is actually materialized, exactly once. The save
  /// below is awaited (unlike other change-driven saves in this screen)
  /// so the granted item is durably persisted before this call returns --
  /// closing the window where the daily allowance was already consumed
  /// but the resulting chest item had not yet reached disk.
  Future<void> _grantRewardedChest(RewardedAdGroup group) async {
    // A group covering more than one ChestCategory (Crew & Equipment)
    // grants a roll from a randomly chosen category within it, so every
    // original category stays obtainable via ads without a dedicated
    // button each -- see RewardedAdGroupLabel.chestCategories.
    final categories = group.chestCategories;
    final category = categories[simulation.rng.nextInt(categories.length)];
    final reward = simulation.openRewardedChest(category);
    setState(() {});
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Received ${reward.name} (${reward.rarity.label})'),
      ),
    );
  }

  Future<void> _grantAdGold() async {
    final reward = simulation.grantAdGold();
    setState(() {});
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Received $reward coins')));
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
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null) {
        final minutes = _now().difference(backgroundedAt).inMinutes;
        final reward = Balance.offlineRewardCoins(
          simulation.progress.tree[FleetTrack.offline] ?? 0,
          minutes,
        );
        if (reward > 0) {
          setState(() => simulation.coins += reward);
          _save();
        }
      }
      game.resumeEngine();
    } else {
      _backgroundedAt = _now();
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
    _closeBehaviorMenu();
    _save();
  }

  void _toggleBehaviorMenu() {
    if (_behaviorMenuOpen) {
      _closeBehaviorMenu();
    } else {
      _openBehaviorMenu();
    }
  }

  void _openBehaviorMenu() {
    _behaviorOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap-outside-to-dismiss, covering the whole screen (this is a
          // top-level Overlay entry, not confined to the map).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeBehaviorMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _behaviorLink,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: const Offset(0, -8),
            child: _behaviorOptions(),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_behaviorOverlayEntry!);
    setState(() => _behaviorMenuOpen = true);
  }

  void _closeBehaviorMenu() {
    _behaviorOverlayEntry?.remove();
    _behaviorOverlayEntry = null;
    if (mounted) setState(() => _behaviorMenuOpen = false);
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
  static const _behaviorModes = [
    BehaviorMode.explorer,
    BehaviorMode.merchant,
    BehaviorMode.pirate,
    BehaviorMode.privateer,
  ];
  static const _behaviorIcons = [
    Icons.explore_outlined,
    Icons.local_shipping_outlined,
    Icons.flag_outlined,
    Icons.shield_outlined,
  ];

  /// The small persistent tag showing the CURRENTLY selected behavior --
  /// replaces what used to be a permanently-expanded selector that
  /// reserved real map space at all times. Tapping it opens
  /// _behaviorOptions as a floating overlay at approximately the same
  /// spot; selecting an option (or tapping the tag again) closes it.
  Widget _behaviorTag() {
    final index = _behaviorModes.indexOf(selected.behavior);
    return CompositedTransformTarget(
      link: _behaviorLink,
      child: Material(
        color: const Color(0xff163845),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffa58e61)),
        ),
        child: InkWell(
          key: const Key('behavior_tag'),
          borderRadius: BorderRadius.circular(20),
          onTap: _toggleBehaviorMenu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  index >= 0 ? _behaviorIcons[index] : Icons.help_outline,
                  size: 18,
                  color: const Color(0xffffd78b),
                ),
                const SizedBox(width: 6),
                Text(
                  selected.behavior.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffffd78b),
                  ),
                ),
                Icon(
                  _behaviorMenuOpen
                      ? Icons.arrow_drop_up
                      : Icons.arrow_drop_down,
                  size: 18,
                  color: const Color(0xffffd78b),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The floating popup's contents (only built while _behaviorMenuOpen).
  Widget _behaviorOptions() => Material(
    color: const Color(0xff0f2b34),
    borderRadius: BorderRadius.circular(10),
    elevation: 8,
    child: Container(
      width: 148,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffa58e61)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _behaviorModes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Tooltip(
                message:
                    '${_behaviorModes[i].name}${selected.playerOwned ? '' : ' (NPC)'}',
                child: Semantics(
                  selected: selected.behavior == _behaviorModes[i],
                  child: TextButton(
                    key: Key('order_${_behaviorModes[i].name}'),
                    onPressed: selected.playerOwned
                        ? () => _order(_behaviorModes[i])
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(120, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: selected.behavior == _behaviorModes[i]
                          ? const Color(0xff526053)
                          : const Color(0xff163845),
                      foregroundColor: selected.behavior == _behaviorModes[i]
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
                        Icon(_behaviorIcons[i], size: 21),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _behaviorModes[i].name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
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
  );

  Widget _map() => Container(
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
          child: Stack(
            children: [
              // The map always gets the FULL area now -- no space is
              // reserved for the behavior selector (previously a fixed
              // 60px carve-out on narrow screens, or a whole side column
              // on wide ones). The tag below is a Positioned overlay
              // drawn on TOP of the map, which never affects a Stack's
              // own sizing. Its popup, when open, is a real Flutter
              // Overlay entry (see _openBehaviorMenu) rather than a
              // Positioned nested in this Stack -- that popup's content
              // can be taller than the map area on short screens (small
              // phones, short landscape), and a Positioned nested here
              // would only be hit-testable within this Stack's own
              // laid-out bounds, silently swallowing taps on the
              // overflowing part.
              Positioned.fill(
                child: GameWidget(key: _gameKey, game: game),
              ),
              Positioned(right: 4, bottom: 8, child: _behaviorTag()),
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
        // Roughly half the previous 56px height, and icon-only (no
        // label) -- the existing icon set already reads fine on its own
        // (storefront/tree/build/sailing/settings), and the selected
        // cell's solid background fill still makes the current tab
        // obvious without needing the text. A Tooltip + Semantics label
        // keep the name available (long-press / screen reader).
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Tooltip(
                    message: managementLabels[i],
                    child: Semantics(
                      selected: tab == i,
                      label: managementLabels[i],
                      child: InkWell(
                        key: Key('tab_${managementLabels[i].toLowerCase()}'),
                        onTap: () => setState(() => tab = i),
                        child: Container(
                          color: tab == i ? const Color(0xff374c4c) : null,
                          alignment: Alignment.center,
                          child: Icon(
                            [
                              Icons.storefront_outlined,
                              Icons.account_tree_outlined,
                              Icons.build_outlined,
                              Icons.sailing_outlined,
                              Icons.settings_outlined,
                            ][i],
                            size: 17,
                            color: tab == i
                                ? const Color(0xffffd78b)
                                : Colors.white54,
                          ),
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
            hasRemoveAds: hasRemoveAds,
            rewardedChests: rewardedChestService,
            rewardedGold: rewardedGoldService,
            billing: billingService,
            onRewardedChestGranted: _grantRewardedChest,
            onAdGoldGranted: _grantAdGold,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    // No AppBar: the redundant "Dot Commander: Pirates" title was removed
    // to recover vertical space, and the banner (below) now sits directly
    // under the status bar instead of a title bar.
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
                    // The permanent ad banner lives at the very top of the
                    // screen now (status bar -> banner -> fleet selector),
                    // recovering the gameplay space it used to occupy at
                    // the bottom, below the map/management area. Same
                    // BannerAdBar instance/logic as before -- only its
                    // position in this Column moved; nothing about its
                    // loading, retry, or Remove Ads collapse behavior
                    // changed, and no second banner is created.
                    BannerAdBar(showAds: !hasRemoveAds),
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
                                Expanded(child: _map()),
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
                                Expanded(child: _map()),
                                // The map stays the dominant element but
                                // gives up a modest share of height here
                                // (.38 -> .48) so the management panel --
                                // and specifically the Deck tab's ship
                                // art -- has substantially more room,
                                // rather than being squeezed into a
                                // small bottom strip.
                                SizedBox(
                                  height: ((c.maxHeight - 80) * .48).clamp(
                                    200.0,
                                    420.0,
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
