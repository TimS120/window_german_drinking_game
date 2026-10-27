import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:window_game/firebase_options.dart';
import 'package:window_game/firebase_room_repository.dart';
import 'package:window_game/game_engine.dart';
import 'package:window_game/game_state_codec.dart';
import 'package:window_game/main.dart';
import 'package:window_game/localization.dart';

import 'localization_test.dart' show MemoryLanguages, chooseLanguage;

import 'package:window_game/rl_policy.dart';
import 'package:window_game/room_social.dart';
import 'package:window_game/room_social_widgets.dart';
import 'package:window_game/windows_firebase_rest.dart';

class _Policy extends WindowRlPolicy {
  @override
  Future<void> preload() async {}
  @override
  Future<AiMoveProposal?> propose(WindowGameEngine game) async {
    final position = game.snapshot().validSelectable.first;
    final option = game.getValidOptionsForCard(position).first;
    return AiMoveProposal(
      action: PolicyAction.guess(
        position: position,
        orientation: option.orientation,
        guess: option.guesses.first,
      ),
      confidence: 0.75,
      source: 'Test model',
      explanation: 'Shared model explanation',
    );
  }
}

class _FailingPolicy extends _Policy {
  @override
  Future<AiMoveProposal?> propose(WindowGameEngine game) async =>
      throw StateError('Test adviser failure');
}

class _Rooms extends FirebaseRoomRepository {
  _Rooms(this.identity, {this.started = true})
    : super(
        transport: WindowsFirebaseRestRoomRepository(
          options: const WindowFirebaseRestOptions(
            apiKey: 'unused',
            databaseUrl: 'https://test.invalid',
          ),
        ),
      );
  final String identity;
  bool started;
  Map<String, String> devices = {};
  int controlId = 0;
  String? controlNotice;
  List<RoomSeat> seats = const [
    RoomSeat(index: 0, name: 'Max', ownerUid: 'host'),
    RoomSeat(index: 1, name: 'Heiko', ownerUid: 'host'),
    RoomSeat(index: 2, name: 'Tom', ownerUid: 'host'),
    RoomSeat(index: 3, name: 'Anna', ownerUid: 'guest'),
  ];
  WindowGameEngine game = WindowGameEngine([
    'Max',
    'Heiko',
    'Tom',
    'Anna',
  ], seed: 1);
  final roomEvents = StreamController<OnlineRoom>.broadcast();
  final socialEvents = StreamController<RoomSocialSnapshot>.broadcast();
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> social = {};
  int version = 7;
  Completer<void>? uiGate;
  @override
  String get uid => identity;
  @override
  Future<String> signInAnonymously() async => uid;
  OnlineRoom get room => OnlineRoom(
    code: 'ABC234',
    version: version,
    hostUid: 'host',
    state: game.publicObservation(),
    started: started,
    seats: seats,
    devices: devices,
    controlId: controlId,
    controlNotice: controlNotice,
  );
  @override
  Future<OnlineRoom?> loadRoom(String code) async => room;
  @override
  Future<GameState?> loadPrivateState(String code) async => game.exportState();
  @override
  Stream<RoomRequest> observeRequests(String code) => const Stream.empty();
  @override
  Stream<OnlineRoom?> observeRoom(String code) async* {
    yield room;
    yield* roomEvents.stream;
  }

  @override
  Stream<RoomSocialSnapshot> observeSocial(String code) async* {
    yield RoomSocialSnapshot(social);
    yield* socialEvents.stream;
  }

  void share(Map<String, dynamic> turn) {
    social['turn'] = {'uid': 'host', 'version': version, ...turn};
    socialEvents.add(RoomSocialSnapshot({...social}));
  }

  @override
  Future<void> publishTurnUi(String code, Map<String, dynamic> turn) async {
    calls.add({'type': 'turnUiDirect', ...turn});
    if (uiGate != null) await uiGate!.future;
    social['turnViews'] = {
      ...socialMap(social['turnViews']),
      uid: {
        ...turn,
        'uid': uid,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
    };
    socialEvents.add(RoomSocialSnapshot({...social}));
  }

  void react(String id) {
    social['reactions'] = {
      'host': {
        'id': id,
        'emoji': '🎉',
        'sender': 'Device 1 (Max, Heiko, Tom)',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
    };
    socialEvents.add(RoomSocialSnapshot({...social}));
  }

  @override
  Future<void> requestSocial({
    required String roomCode,
    required String type,
    required Map<String, dynamic> action,
    int expectedVersion = -1,
  }) async {
    calls.add({'type': type, ...action});
    if (type == 'turnUi') share(action);
    if (type == 'chat') {
      social['messages'] = {
        'message': {
          'sender': roomDeviceLabel(room.seats, uid),
          'text': action['text'],
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        },
      };
      socialEvents.add(RoomSocialSnapshot({...social}));
    }
    if (type == 'reaction') react('sent');
  }

  @override
  Future<void> requestAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) async {
    calls.add(action);
    if (action['type'] == 'guess') {
      final position = Position(action['position'][0], action['position'][1]);
      final option = game
          .getValidOptionsForCard(position)
          .firstWhere((o) => o.orientation.name == action['orientation']);
      game.applyGuess(
        position,
        option,
        GuessType.values.byName(action['guess']),
      );
      version++;
      social.remove('turn');
      roomEvents.add(room);
      socialEvents.add(RoomSocialSnapshot({...social}));
    }
  }

  Future<void> close() async {
    if (uiGate != null && !uiGate!.isCompleted) uiGate!.complete();
    await roomEvents.close();
    await socialEvents.close();
  }
}

/// Uses the real GameShell host queue rather than simulating host acceptance.
class _HostRooms extends _Rooms {
  _HostRooms() : super('host');
  final requests = StreamController<RoomRequest>.broadcast();
  int loads = 0;
  final publishedVersions = <int>[];
  Completer<void>? chatGate;
  Completer<void>? cleanupGate;
  @override
  Stream<RoomRequest> observeRequests(String code) => requests.stream;

  @override
  Future<RoomSocialSnapshot> loadSocial(String code) async {
    loads++;
    if (chatGate != null) await chatGate!.future;
    return RoomSocialSnapshot({...social});
  }

  @override
  Future<void> publishSocial(String code, Map<String, dynamic> patch) async {
    social = RoomSocialSnapshot(social).updated(patch).data;
    socialEvents.add(RoomSocialSnapshot({...social}));
  }

  @override
  Future<void> requestSocial({
    required String roomCode,
    required String type,
    required Map<String, dynamic> action,
    int expectedVersion = -1,
  }) async {
    calls.add({'type': type, ...action});
    requests.add(
      RoomRequest(
        id: 'request${calls.length}',
        uid: uid,
        type: type,
        action: action,
        expectedVersion: expectedVersion,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> deleteRequest(String roomCode, String requestId) async {
    if (cleanupGate != null) await cleanupGate!.future;
  }

  @override
  Future<void> requestAction({
    required String roomCode,
    required int expectedVersion,
    required Map<String, dynamic> action,
  }) async {
    calls.add(action);
    requests.add(
      RoomRequest(
        id: 'request${calls.length}',
        uid: uid,
        type: 'action',
        action: action,
        expectedVersion: expectedVersion,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> publishState({
    required String roomCode,
    required String hostUid,
    required int version,
    required List<RoomSeat> seats,
    required GameState state,
    required bool started,
    bool developerMode = false,
    Map<String, dynamic> roomMetadata = const {},
  }) async {
    this.version = version;
    this.started = started;
    this.seats = seats;
    devices = Map<String, String>.from(roomMetadata['devices'] as Map? ?? {});
    controlId = roomMetadata['controlId'] as int? ?? 0;
    controlNotice = roomMetadata['controlNotice'] as String?;
    publishedVersions.add(version);
    game = WindowGameEngine.fromState(state);
    social.remove('turn');
    roomEvents.add(room);
    socialEvents.add(RoomSocialSnapshot({...social}));
  }

  @override
  Future<void> close() async {
    if (chatGate != null && !chatGate!.isCompleted) chatGate!.complete();
    if (cleanupGate != null && !cleanupGate!.isCompleted) {
      cleanupGate!.complete();
    }
    await requests.close();
    await super.close();
  }
}

class _GuestTurnRooms extends _Rooms {
  _GuestTurnRooms() : super('guest');
  @override
  OnlineRoom get room {
    final base = super.room;
    return OnlineRoom(
      code: base.code,
      version: base.version,
      hostUid: base.hostUid,
      state: base.state,
      started: base.started,
      seats: [
        for (final seat in base.seats)
          RoomSeat(
            index: seat.index,
            name: seat.name,
            ownerUid: seat.index == 0 ? 'guest' : seat.ownerUid,
          ),
      ],
    );
  }
}

final _previewKey = GlobalKey();
Future<void> _preview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('UI_PREVIEW_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        _previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _joinTest(
  WidgetTester tester,
  _Rooms rooms,
  Size size, {
  LanguageController? language,
  WindowRlPolicy? policy,
}) async {
  const previewFont = String.fromEnvironment('UI_PREVIEW_FONT');
  const previewEmojiFont = String.fromEnvironment('UI_PREVIEW_EMOJI_FONT');
  if (previewFont.isNotEmpty) {
    await tester.runAsync(() async {
      final loader = FontLoader('PreviewFont')
        ..addFont(
          File(previewFont).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      if (previewEmojiFont.isNotEmpty) {
        final emojis = FontLoader('PreviewEmoji')
          ..addFont(
            File(previewEmojiFont)
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          );
        await emojis.load();
      }
    });
  }
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(rooms.close);
  Widget app() => MaterialApp(
    locale: language?.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: previewFont.isEmpty ? null : 'PreviewFont',
        fontFamilyFallback: previewEmojiFont.isEmpty ? null : ['PreviewEmoji'],
      ),
    ),
    home: GameShell(
      firebaseEnabled: true,
      browserGuest: true,
      initialRoomCode: 'ABC234',
      rlPolicy: policy ?? _Policy(),
      repository: rooms,
    ),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _previewKey,
      child: language == null
          ? app()
          : LanguageScope(
              controller: language,
              child: AnimatedBuilder(
                animation: language,
                builder: (context, _) => app(),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Players on this device'),
    'Anna',
  );
  await tester.ensureVisible(find.text('Join online room'));
  await tester.tap(find.text('Join online room'));
  await tester.pumpAndSettle();
  if (rooms is _HostRooms) {
    // Let the broadcast subscription cancellation finish outside FakeAsync,
    // then pump the continuation that restores the host's request listener.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('canceling a restart leaves the game unchanged', (tester) async {
    final rooms = _HostRooms();
    await _joinTest(tester, rooms, const Size(1400, 1000));
    final before = GameStateCodec.encode(rooms.game.exportState());
    await tester.tap(find.byKey(const ValueKey('restart-online-game')));
    await tester.pumpAndSettle();
    expect(find.text('Restart the game?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rooms.publishedVersions, isEmpty);
    expect(GameStateCodec.encode(rooms.game.exportState()), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all guests see each restart notice once and can dismiss it', (
    tester,
  ) async {
    final rooms = _Rooms('guest')
      ..controlId = 3
      ..controlNotice = 'restart';
    await _joinTest(tester, rooms, const Size(390, 844));
    expect(find.text('The host restarted the game'), findsNothing);
    rooms.controlId++;
    rooms.version++;
    rooms.roomEvents.add(rooms.room);
    await tester.pumpAndSettle();
    expect(find.text('The host restarted the game'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-notice')));
    await tester.pump();
    rooms.roomEvents.add(rooms.room);
    await tester.pumpAndSettle();
    expect(find.text('The host restarted the game'), findsNothing);
    rooms.controlId++;
    rooms.version++;
    rooms.roomEvents.add(rooms.room);
    await tester.pumpAndSettle();
    expect(find.text('The host restarted the game'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('The host restarted the game'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'host reopens same lobby and can edit empty physical device groups',
    (tester) async {
      final rooms = _HostRooms();
      rooms.social['messages'] = {
        'keep': {'sender': 'Anna', 'text': 'Keep chat', 'createdAt': 1},
      };
      await _joinTest(tester, rooms, const Size(1400, 1000));
      await tester.tap(find.byKey(const ValueKey('host-controls')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return to lobby'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(rooms.started, isFalse);
      expect(rooms.room.code, 'ABC234');
      expect(rooms.social['messages']['keep']['text'], 'Keep chat');
      expect(find.text('Window lobby'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-notice')));
      await tester.pumpAndSettle();
      Future<void> edit(String names) async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-device:guest')),
        );
        await tester.tap(find.byKey(const ValueKey('edit-device:guest')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('device-label')),
          'Kitchen',
        );
        await tester.enterText(
          find.byKey(const ValueKey('device-players')),
          names,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
      }

      await edit('Ben, Carla');
      expect(rooms.room.deviceLabels['guest'], 'Kitchen');
      expect(
        rooms.room.seats
            .where((s) => s.ownerUid == 'guest')
            .map((s) => s.name)
            .toList(),
        ['Ben', 'Carla'],
      );
      await edit('');
      expect(rooms.room.seats.where((s) => s.ownerUid == 'guest'), isEmpty);
      expect(find.text('No players assigned'), findsOneWidget);
      await edit('Dana');
      expect(rooms.room.seats.last.name, 'Dana');
      expect(rooms.room.seats.last.ownerUid, 'guest');
      await tester.ensureVisible(find.text('Start game and lock lobby'));
      await tester.tap(find.text('Start game and lock lobby'));
      await tester.pumpAndSettle();
      expect(rooms.started, isTrue);
      expect(rooms.game.players, ['Max', 'Heiko', 'Tom', 'Dana']);
      expect(rooms.room.code, 'ABC234');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'portrait board owns turn buttons and deck count without routine room/model status',
    (tester) async {
      await _joinTest(tester, _GuestTurnRooms(), const Size(390, 844));
      final boardEnd = find.byKey(const ValueKey('board-end-turn'));
      final boardPropose = find.byKey(const ValueKey('board-propose'));
      final deck = find.byKey(const ValueKey('board-deck-counter'));
      expect(boardEnd, findsOneWidget);
      expect(boardPropose, findsOneWidget);
      expect(deck, findsOneWidget);
      final handle = tester.getRect(find.byKey(const ValueKey('card:2:5')));
      expect(tester.getRect(deck).bottom, lessThan(handle.top));
      expect(tester.getRect(boardEnd).top, greaterThan(handle.bottom));
      expect(
        tester.getRect(boardPropose).top,
        greaterThan(tester.getRect(boardEnd).bottom),
      );
      expect(find.text('ONNX policy loaded.'), findsNothing);
      expect(find.textContaining('Online room:'), findsNothing);
      expect(find.textContaining('Room ABC234:'), findsNothing);
      expect(
        find.text('Waiting for the player who owns this seat.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      final cardImages = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.startsWith('assets/cards/'),
      );
      final imageSizes = cardImages
          .evaluate()
          .map((element) => tester.getSize(find.byWidget(element.widget)))
          .toList();
      expect(imageSizes.length, greaterThan(1));
      for (final size in imageSizes) {
        expect(size.width, closeTo(imageSizes.first.width, 0.001));
        expect(size.height, closeTo(imageSizes.first.height, 0.001));
      }
      await _preview(tester, 'portrait-board-controls');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('adviser failures appear as red local system chat messages', (
    tester,
  ) async {
    await _joinTest(
      tester,
      _GuestTurnRooms(),
      const Size(1400, 1000),
      policy: _FailingPolicy(),
    );
    await tester.tap(find.text('Propose best move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RL model'));
    await tester.pumpAndSettle();
    final error = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.textSpan?.toPlainText().contains('Test adviser failure') ?? false),
    );
    expect(error, findsOneWidget);
    final text = tester.widget<Text>(error);
    expect(
      text.textSpan!.style!.color,
      Theme.of(tester.element(error)).colorScheme.error,
    );
    expect(text.textSpan!.toPlainText(), contains('System:'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'host can reset during a guest turn while preserving room, seats and chat',
    (tester) async {
      final rooms = _HostRooms();
      final state = GameStateCodec.encode(rooms.game.exportState());
      state['currentPlayerIndex'] = 3;
      rooms.game = WindowGameEngine.fromState(GameStateCodec.decode(state));
      rooms.social['messages'] = {
        'saved': {'sender': 'Anna', 'text': 'Keep this chat', 'createdAt': 1},
      };
      final seats = rooms.room.seats.map((seat) => seat.toJson()).toList();
      await _joinTest(tester, rooms, const Size(1400, 1000));
      expect(find.text('Anna is playing'), findsOneWidget);
      final restart = find.byKey(const ValueKey('restart-online-game'));
      expect(tester.widget<IconButton>(restart).onPressed, isNotNull);
      await tester.tap(restart);
      await tester.pumpAndSettle();
      expect(rooms.publishedVersions, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(rooms.publishedVersions, [8]);
      expect(rooms.game.currentPlayer, 'Max');
      expect(rooms.room.code, 'ABC234');
      expect(rooms.room.seats.map((seat) => seat.toJson()).toList(), seats);
      expect(rooms.social['messages']['saved']['text'], 'Keep this chat');
      expect(rooms.game.exportState().currentPlayerIndex, 0);
      expect(
        rooms.game.snapshot().stats.values.every(
          (stats) =>
              stats.correct == 0 && stats.wrong == 0 && stats.drinks == 0,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('guest never receives the online restart control', (
    tester,
  ) async {
    await _joinTest(tester, _Rooms('guest'), const Size(1400, 1000));
    expect(find.byKey(const ValueKey('restart-online-game')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'host restarts a completed game in the same room with the same seats',
    (tester) async {
      final rooms = _HostRooms();
      final state = GameStateCodec.encode(rooms.game.exportState());
      state['faceUp'] = windowLayout.map((row) => row.toList()).toList();
      state['turnCanEnd'] = true;
      rooms.game = WindowGameEngine.fromState(GameStateCodec.decode(state));
      expect(rooms.game.gameEnded, isTrue);
      final originalSeats = rooms.room.seats
          .map((seat) => seat.toJson())
          .toList();
      await _joinTest(tester, rooms, const Size(1400, 1000));
      expect(find.text('You won!'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Restart game'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(rooms.publishedVersions, [8]);
      expect(rooms.room.code, 'ABC234');
      expect(
        rooms.room.seats.map((seat) => seat.toJson()).toList(),
        originalSeats,
      );
      expect(rooms.game.gameEnded, isFalse);
      expect(rooms.game.currentPlayer, 'Max');
      expect(find.text('The host restarted the game'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'accepted lobby exposes the language selector without rejoining',
    (tester) async {
      final rooms = _Rooms('guest', started: false);
      final language = LanguageController(
        store: MemoryLanguages(),
        initialLocale: const Locale('en'),
      );
      addTearDown(language.dispose);
      await _joinTest(
        tester,
        rooms,
        const Size(1400, 1000),
        language: language,
      );
      expect(find.text('Window lobby'), findsOneWidget);
      await chooseLanguage(tester, 'Choose language', 'Deutsch');
      expect(find.text('Fenster-Lobby'), findsOneWidget);
      expect(find.text('Raum ABC234'), findsOneWidget);
      expect(find.textContaining('Lobby ABC234: Warte'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(rooms.calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(1400, 1000), const Size(390, 844)]) {
    testWidgets(
      'shared view changes language locally and preserves chat at $size',
      (tester) async {
        final rooms = _Rooms('guest');
        rooms.social['messages'] = {
          'existing': {
            'uid': 'host',
            'sender': 'Device 1 (Max, Heiko, Tom)',
            'text': 'Higher, hello!',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          },
        };
        final language = LanguageController(
          store: MemoryLanguages(),
          initialLocale: const Locale('en'),
        );
        addTearDown(language.dispose);
        await _joinTest(tester, rooms, size, language: language);
        final position = rooms.game.snapshot().validSelectable.first;
        final option = rooms.game.getValidOptionsForCard(position).first;
        rooms.share({
          'stage': 'guess',
          'row': position.row,
          'column': position.column,
          'orientation': option.orientation.name,
          'proposal': encodeSharedProposal(
            AiMoveProposal(
              action: PolicyAction.guess(
                position: position,
                orientation: option.orientation,
                guess: option.guesses.first,
              ),
              confidence: 0.75,
              source: 'Pure statistics',
              expectedDrinks: 1.5,
              explanation: 'Low risk, small penalty',
            ),
          ),
        });
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Message everyone…'),
          'Untranslated draft 🍻',
        );
        await chooseLanguage(tester, 'Choose language', 'Deutsch');
        expect(find.text('Dein Tipp'), findsOneWidget);
        expect(
          find.textContaining('Gerät 1 (Max, Heiko, Tom): Higher, hello!'),
          findsOneWidget,
        );
        expect(find.text('Zugansicht von Max'), findsOneWidget);
        expect(
          find.text('Geringes Risiko, wenige Strafschlucke'),
          findsOneWidget,
        );
        expect(
          find.textContaining('geschätzte verbleibende Schlucke 1,5'),
          findsOneWidget,
        );
        expect(find.text('Untranslated draft 🍻'), findsOneWidget);
        expect(rooms.calls, isEmpty);
        expect(rooms.version, 7);
        await _preview(tester, 'german-${size.width.toInt()}');
        await tester.tap(find.byTooltip('Chat minimieren'));
        await tester.pumpAndSettle();
        await chooseLanguage(tester, 'Sprache wählen', 'English');
        expect(find.byType(RoomChatPanel), findsNothing);
        expect(find.text('Your guess'), findsOneWidget);
        await tester.tap(find.byTooltip('Open chat'));
        await tester.pumpAndSettle();
        expect(find.text('Untranslated draft 🍻'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('narrow desktop windows keep chat at the right', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _joinTest(tester, _Rooms('guest'), const Size(500, 800));
    final chat = find.byType(RoomChatPanel);
    expect(tester.getRect(chat).right, 500);
    expect(tester.getRect(chat).top, lessThan(100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Minimize chat'));
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final size in [
    const Size(1400, 1000),
    const Size(768, 1024),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('chat layout and minimizing reclaim game space at $size', (
      tester,
    ) async {
      final rooms = _Rooms('guest');
      await _joinTest(tester, rooms, size);
      final chat = find.byType(RoomChatPanel);
      final card = find.byKey(const ValueKey('card:0:0'));
      final stats = find.text('Current player');
      final phone = size.shortestSide < 600;
      final chatRect = tester.getRect(chat);
      if (phone) {
        expect(chatRect.top, greaterThan(tester.getRect(stats).bottom));
      } else {
        if (size.height > size.width) {
          expect(tester.getRect(card).top, lessThan(tester.getRect(stats).top));
          expect(find.byKey(const ValueKey('board-end-turn')), findsOneWidget);
        } else {
          expect(
            tester.getRect(card).right,
            lessThan(tester.getRect(stats).left),
          );
        }
        expect(tester.getRect(stats).right, lessThan(chatRect.left));
        expect(chatRect.height, greaterThan(size.height * 0.7));
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Message everyone…'),
        'Saved draft',
      );
      final gameArea = tester.getRect(find.byType(SafeArea).first);
      await tester.tap(find.byTooltip('Minimize chat'));
      await tester.pumpAndSettle();
      expect(chat, findsNothing);
      expect(find.byTooltip('Open chat'), findsOneWidget);
      final largerArea = tester.getRect(find.byType(SafeArea).first);
      expect(
        phone ? largerArea.height : largerArea.width,
        greaterThan(phone ? gameArea.height : gameArea.width),
      );
      // Messages keep arriving while the panel is hidden.
      await rooms.requestSocial(
        roomCode: 'ABC234',
        type: 'chat',
        action: {'text': 'While minimized'},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open chat'));
      await tester.pumpAndSettle();
      expect(chat, findsOneWidget);
      expect(find.text('Saved draft'), findsOneWidget);
      expect(find.textContaining('While minimized'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _preview(
        tester,
        'chat-layout-${size.width.toInt()}x${size.height.toInt()}',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'a stalled view upload cannot delay a guest selecting or submitting a guess',
    (tester) async {
      final rooms = _GuestTurnRooms();
      await _joinTest(tester, rooms, const Size(1400, 1000));
      rooms.uiGate = Completer<void>();
      final position = rooms.game.snapshot().validSelectable.first;
      await tester.tap(
        find.byKey(ValueKey('card:${position.row}:${position.column}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your guess'), findsOneWidget);
      final beforeDrag = tester.getCenter(find.text('Your guess'));
      await tester.drag(find.text('Your guess'), const Offset(30, 15));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.text('Your guess')).dx,
        greaterThan(beforeDrag.dx),
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(rooms.uiGate!.isCompleted, isFalse);
      await tester.tap(find.text('Higher'));
      await tester.pumpAndSettle();
      expect(rooms.calls.where((c) => c['type'] == 'guess').length, 1);
      expect(rooms.calls.where((c) => c['type'] == 'turnUi'), isEmpty);
      expect(rooms.version, 8);
      expect(rooms.uiGate!.isCompleted, isFalse);
      expect(find.text('Your guess'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'stalled chat relay and cleanup cannot block successive gameplay requests',
    (tester) async {
      final rooms = _HostRooms();
      await _joinTest(tester, rooms, const Size(1400, 1000));
      rooms.chatGate = Completer<void>();
      rooms.cleanupGate = Completer<void>();
      rooms.requests.add(
        RoomRequest(
          id: 'slow-chat',
          uid: 'guest',
          type: 'chat',
          action: {'text': 'Hello'},
          expectedVersion: 7,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await tester.pumpAndSettle();
      expect(rooms.loads, 1);
      final position = rooms.game.snapshot().validSelectable.first;
      final option = rooms.game.getValidOptionsForCard(position).first;
      rooms.requests.add(
        RoomRequest(
          id: 'first-move',
          uid: 'host',
          type: 'action',
          action: {
            'type': 'guess',
            'position': [position.row, position.column],
            'orientation': option.orientation.name,
            'guess': option.guesses.first.name,
          },
          expectedVersion: 7,
        ),
      );
      await tester.pumpAndSettle();
      expect(rooms.publishedVersions, [8]);
      final next = rooms.game.pendingRemovals.isNotEmpty
          ? 'confirmRemovals'
          : rooms.game.snapshot().pendingSamePosition != null
          ? 'confirmSame'
          : 'endTurn';
      rooms.requests.add(
        RoomRequest(
          id: 'second-move',
          uid: 'host',
          type: 'action',
          action: {'type': next},
          expectedVersion: 8,
        ),
      );
      await tester.pumpAndSettle();
      expect(rooms.publishedVersions, [8, 9]);
      expect(rooms.chatGate!.isCompleted, isFalse);
      expect(rooms.cleanupGate!.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'floating emojis and sender names have no fallback underline outside a Scaffold',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoomReactionLayer(
            reactions: [
              {'id': 'test', 'emoji': '😂', 'sender': 'Anna'},
            ],
            reducedMotion: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      for (final finder in [find.text('😂'), find.text('Anna')]) {
        for (final element in finder.evaluate()) {
          final paragraph = element.findRenderObject() as RenderParagraph;
          expect(
            paragraph.text.style?.decoration ?? TextDecoration.none,
            TextDecoration.none,
          );
        }
      }
      expect(find.text('😂'), findsNWidgets(5));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'phone spectator sees legal borders, advice and read-only guesses while chatting',
    (tester) async {
      final rooms = _Rooms('guest');
      await _joinTest(tester, rooms, const Size(390, 844));
      expect(find.text('Room chat · Anna'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      final position = rooms.game.snapshot().validSelectable.first;
      final option = rooms.game.getValidOptionsForCard(position).first;
      final proposal = AiMoveProposal(
        action: PolicyAction.guess(
          position: position,
          orientation: option.orientation,
          guess: option.guesses.first,
        ),
        confidence: 0.75,
        source: 'Pure statistics',
        explanation: 'Shared reason',
        expectedDrinks: 2,
      );
      rooms.share({
        'stage': 'guess',
        'row': position.row,
        'column': position.column,
        'orientation': option.orientation.name,
        'proposal': encodeSharedProposal(proposal),
      });
      await tester.pumpAndSettle();
      expect(find.text('Your guess'), findsOneWidget);
      expect(find.text('Watching Max'), findsOneWidget);
      final guess = find.widgetWithText(FilledButton, 'Higher · suggested');
      expect(tester.widget<FilledButton>(guess).onPressed, isNull);
      await _preview(tester, 'phone-spectator');
      final borders = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.foregroundDecoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.border)
          .whereType<Border>();
      expect(
        borders.any((border) => border.top.color == Colors.lightBlueAccent),
        isTrue,
      );
      expect(
        borders
            .where(
              (border) =>
                  border.top.color == Colors.amber ||
                  border.top.color == Colors.lightBlueAccent,
            )
            .length,
        greaterThanOrEqualTo(rooms.game.snapshot().validSelectable.length),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Message everyone…'),
        'Hello 😂',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anna: Hello 😂'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byTooltip('Send message')).bottom,
        lessThanOrEqualTo(524),
      );
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Release 🎉 for everyone'));
      await tester.pump(const Duration(milliseconds: 350));
      await _preview(tester, 'phone-reaction');
      expect(find.byType(RoomReactionLayer), findsOneWidget);
      expect(find.text('Device 1 (Max, Heiko, Tom)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Device 1 (Max, Heiko, Tom)'), findsNothing);
      final reconnect = {
        ...rooms.social,
        'reactions': {
          'host': {
            'id': 'missed-during-disconnect',
            'sender': 'Max',
            'emoji': '😂',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          },
        },
      };
      rooms.socialEvents.add(
        RoomSocialSnapshot(reconnect, isFullSnapshot: true),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(RoomReactionLayer),
          matching: find.text('Max'),
        ),
        findsNothing,
      );
      // A duplicate snapshot must not restart the burst.
      rooms.socialEvents.add(RoomSocialSnapshot({...rooms.social}));
      await tester.pump();
      expect(find.text('Device 1 (Max, Heiko, Tom)'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'active device selects a card and guess without losing access to chat',
    (tester) async {
      final rooms = _HostRooms();
      await _joinTest(tester, rooms, const Size(1400, 1000));
      expect(
        find.text('Room chat · Device 1 (Max, Heiko, Tom)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Propose best move'));
      await tester.pumpAndSettle();
      expect(find.text('Best-move prediction'), findsOneWidget);
      await tester.tap(find.text('RL model'));
      await tester.pumpAndSettle();
      expect(find.text('Shared model explanation'), findsOneWidget);
      expect(rooms.social['turnViews']['host']['stage'], 'suggestion');
      final position = rooms.game.snapshot().validSelectable.first;
      await tester.tap(
        find.byKey(ValueKey('card:${position.row}:${position.column}')),
      );
      await tester.pumpAndSettle();
      if (find.textContaining('Choose the comparison').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Horizontal cards').first);
        await tester.pumpAndSettle();
      }
      expect(find.text('Your guess'), findsOneWidget);
      await _preview(tester, 'desktop-turn');
      await tester.tap(find.byTooltip('Minimize chat'));
      await tester.pumpAndSettle();
      expect(find.text('Your guess'), findsOneWidget);
      await tester.tap(find.byTooltip('Open chat'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomChatPanel), findsOneWidget);
      expect(find.text('Your guess'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Message everyone…'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Higher · suggested'));
      await tester.pumpAndSettle();
      expect(rooms.calls.where((c) => c['type'] == 'guess'), isEmpty);
      expect(rooms.publishedVersions, [8]);
      expect(find.text('Your guess'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(rooms.loads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'compact chat supports keyboard-sized viewports and reduced effects',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reduced = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: RoomChatPanel(
              sender: 'Anna',
              messages: const [],
              onSend: (_) async {},
              onReact: (_) async {},
              reducedMotion: false,
              onReducedMotion: (value) => reduced = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Reduce reaction animations'));
      expect(reduced, isTrue);
      await tester.tap(find.byTooltip('Expand chat history'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
