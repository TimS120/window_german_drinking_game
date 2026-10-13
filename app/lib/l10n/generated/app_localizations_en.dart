// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Window';

  @override
  String get language => 'Language';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get choosePlayers => 'Choose player names to begin a local game.';

  @override
  String get browserJoinInstructions =>
      'Enter the room code shared by your host and your player names.';

  @override
  String get browserUnavailable =>
      'Browser joining is unavailable: this build has no Firebase configuration.';

  @override
  String get firebaseUnavailable =>
      'Firebase is not configured for this build yet.';

  @override
  String get enterPlayer => 'Enter at least one player on this device.';

  @override
  String get uniquePlayers =>
      'Every player sharing this device needs a unique name.';

  @override
  String get validRoomCode =>
      'Enter the six-character room code shared by your host.';

  @override
  String get roomNotFound => 'Room not found. Check the room code.';

  @override
  String get waitingAcceptance =>
      'Waiting for the host to accept your player names…';

  @override
  String get hostTimeout =>
      'The host did not respond. Ask them to keep the lobby open, then try again.';

  @override
  String get roomUnavailable => 'This room is no longer available.';

  @override
  String get joinInstructions =>
      'Enter a room code and your player names to join.';

  @override
  String get chatReconnecting => 'Room chat is reconnecting…';

  @override
  String get sharingUnavailable =>
      'Turn sharing is temporarily unavailable. Gameplay remains available.';

  @override
  String get openChat => 'Open chat';

  @override
  String get minimizeChat => 'Minimize chat';

  @override
  String get chooseComparison => 'Choose the comparison';

  @override
  String get horizontalCards => 'Horizontal cards';

  @override
  String get verticalCards => 'Vertical cards';

  @override
  String get betweenOutside => 'In-between or outside';

  @override
  String get higherSameLower => 'Higher, same, or lower';

  @override
  String get yourGuess => 'Your guess';

  @override
  String get higher => 'Higher';

  @override
  String get same => 'Same';

  @override
  String get lower => 'Lower';

  @override
  String get inBetween => 'In-between';

  @override
  String get outside => 'Outside';

  @override
  String get bestMovePrediction => 'Best-move prediction';

  @override
  String get rlModel => 'RL model';

  @override
  String get pureStatistics => 'Pure statistics';

  @override
  String get statisticsDescription =>
      'Estimate your future drinks using public card history.';

  @override
  String get findingMove => 'Finding best move…';

  @override
  String get submittingMove => 'Submitting move…';

  @override
  String get moveSent => 'Move request sent to host.';

  @override
  String get finishPendingProposal =>
      'Finish the pending action before requesting a proposal.';

  @override
  String get startingGame => 'Starting game…';

  @override
  String get cardUnavailable => 'That card cannot be selected yet.';

  @override
  String get sameCorrect => 'Correct: same rank!';

  @override
  String get continueGame => 'Continue';

  @override
  String get windowComplete => 'The window is complete!';

  @override
  String get correctContinue =>
      'Correct. You may guess again or end your turn.';

  @override
  String get wrongRedeal =>
      'Wrong guess. The revealed card and every card with a red border will be redealt.';

  @override
  String get wrongGuess => 'Wrong guess';

  @override
  String get redealCards => 'Redeal cards';

  @override
  String get joinWindow => 'Join Window';

  @override
  String get browserDescription =>
      'Play with friends, directly in your browser. No installation required.';

  @override
  String get askHost =>
      'Ask your host to create a lobby in the smartphone or PC/laptop app and share its room code.';

  @override
  String get roomCode => 'Room code';

  @override
  String get devicePlayers => 'Players on this device';

  @override
  String get namesHelper => 'One or more names, separated by commas.';

  @override
  String get separateNames => 'Separate names with commas.';

  @override
  String get joining => 'Joining…';

  @override
  String get joinOnline => 'Join online room';

  @override
  String get localDescription =>
      'A local, cross-platform edition of the German card game.';

  @override
  String get players => 'Players';

  @override
  String get startLocal => 'Start local game';

  @override
  String get createLobby => 'Create online lobby';

  @override
  String get firebaseSetupNeeded => 'Online rooms need Firebase setup';

  @override
  String get windowLobby => 'Window lobby';

  @override
  String get leaveLobby => 'Leave lobby and return to menu';

  @override
  String get shareCode =>
      'Share this code. Players may join until you start the game.';

  @override
  String get waitingStart =>
      'You are in the lobby. Waiting for the host to start.';

  @override
  String get friendsJoin =>
      'Friends can join in the app with this room code, or in their browser at:';

  @override
  String get browserCodeHelp =>
      'Browser players enter the room code above. No installation required.';

  @override
  String get copyBrowser => 'Copy browser address';

  @override
  String get host => 'Host';

  @override
  String get startLockLobby => 'Start game and lock lobby';

  @override
  String get leaveRoom => 'Leave room and return to menu';

  @override
  String get returnMenu => 'Return to menu';

  @override
  String get currentPlayer => 'Current player';

  @override
  String get newLocal => 'New local game';

  @override
  String get waitingPlayer => 'Waiting for the player who owns this seat.';

  @override
  String get handleRule =>
      'Handle rule: choose a card directly beside the handle.';

  @override
  String get hostDeck => 'Deck: managed by host';

  @override
  String get endTurn => 'End turn';

  @override
  String get endTurnSuggested => 'End turn · suggested';

  @override
  String get confirmSame => 'Confirm same-rank penalty';

  @override
  String get redealMarked => 'Redeal marked cards';

  @override
  String get proposeMove => 'Propose best move';

  @override
  String get scoreboard => 'Scoreboard';

  @override
  String get player => 'Player';

  @override
  String get drinks => 'Drinks';

  @override
  String get correct => 'Correct';

  @override
  String get wrong => 'Wrong';

  @override
  String get ratio => 'C/W ratio';

  @override
  String get changed => 'Changed';

  @override
  String get turns => 'Turns';

  @override
  String get total => 'Total';

  @override
  String get sayHello => 'Say hello to your room!';

  @override
  String get enableReactions => 'Enable flying reactions';

  @override
  String get reduceReactions => 'Reduce reaction animations';

  @override
  String get collapseHistory => 'Collapse chat history';

  @override
  String get expandHistory => 'Expand chat history';

  @override
  String get messageHint => 'Message everyone…';

  @override
  String get sendMessage => 'Send message';

  @override
  String get waitMessage =>
      'Please wait a moment before sending another message.';

  @override
  String get messageFailed => 'Message could not be sent. Please retry.';

  @override
  String get reactionFailed => 'Reaction could not be sent. Please retry.';

  @override
  String get modelLoaded => 'ONNX policy loaded.';

  @override
  String get testModelLoaded => 'ONNX test model loaded.';

  @override
  String get modelWillLoad =>
      'Bundled ONNX test model will load when you request a proposal.';

  @override
  String get modelLoading => 'Loading bundled ONNX model…';

  @override
  String get modelUnavailable =>
      'Model unavailable; using the pure-statistics fallback.';

  @override
  String get modelSource => 'ONNX policy';

  @override
  String get testModelSource => 'ONNX test model (untrained)';

  @override
  String get fallbackSource => 'ONNX inference failed → Pure statistics';

  @override
  String get passAction => 'end turn (pass)';

  @override
  String get horizontal => 'horizontal';

  @override
  String get vertical => 'vertical';

  @override
  String get noImmediateDrinks => 'no immediate drinks';

  @override
  String get estimatedSuccess => 'estimated success';

  @override
  String get modelConfidence => 'model confidence';

  @override
  String get passExplanation => 'Pass to avoid more risk';

  @override
  String get certainExplanation => 'Certain guess, no immediate drinks';

  @override
  String get smallPenaltyExplanation => 'Low risk, small penalty';

  @override
  String get futureDrinksExplanation => 'Lower expected future drinks';

  @override
  String get strongOddsExplanation => 'Strong odds, lower future risk';

  @override
  String get pendingAction => 'Finish the pending action first.';

  @override
  String get invalidSelection => 'Invalid card selection.';

  @override
  String get invalidGuess => 'Invalid guess.';

  @override
  String get noSamePending => 'No same guess is pending.';

  @override
  String get enterName => 'Enter at least one player name.';

  @override
  String get uniqueDeviceNames =>
      'Every player on this device needs a unique name.';

  @override
  String get gameAlreadyStarted =>
      'This game has already started. Ask the host for a new lobby.';

  @override
  String get deviceAlreadyJoined => 'This device has already joined the lobby.';

  @override
  String get uniqueLobbyNames =>
      'Player names must be unique in the lobby. Choose other names.';

  @override
  String get rejoinRoom => 'Please rejoin the room.';

  @override
  String get signInExpired => 'Firebase sign-in expired. Please rejoin.';

  @override
  String get reserveRoomFailed =>
      'Could not reserve a room code. Please try again.';

  @override
  String playerStarts(String player) {
    return '$player starts. Select a card next to the handle.';
  }

  @override
  String roomTurn(String code, String player) {
    return 'Room $code: $player\'s turn.';
  }

  @override
  String playerTurn(String player) {
    return '$player\'s turn.';
  }

  @override
  String lobbyWaiting(String code) {
    return 'Lobby $code: waiting for the host to start.';
  }

  @override
  String restoringHost(String code) {
    return 'Restoring host state for room $code…';
  }

  @override
  String createFailed(String error) {
    return 'Could not create room: $error';
  }

  @override
  String joinFailed(String error) {
    return 'Could not join room: $error';
  }

  @override
  String connectionFailed(String error) {
    return 'Room connection failed: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'The host state could not be restored: $error';
  }

  @override
  String moveRejected(String error) {
    return 'Move rejected: $error';
  }

  @override
  String predictionFailed(String error) {
    return 'Prediction failed: $error';
  }

  @override
  String startFailed(String error) {
    return 'Could not start the lobby: $error';
  }

  @override
  String requestFailed(String error) {
    return 'Room request failed: $error';
  }

  @override
  String hostRequestFailed(String error) {
    return 'Room host request error: $error';
  }

  @override
  String invalidRequest(String error) {
    return 'Ignored invalid room request: $error';
  }

  @override
  String suggestedMove(String move) {
    return 'Suggested move: $move.';
  }

  @override
  String suggestedGuess(String guess) {
    return '$guess · suggested';
  }

  @override
  String watchingPlayer(String player) {
    return 'Watching $player';
  }

  @override
  String samePenalty(String player) {
    return 'Every other player takes one swallow. $player can continue after confirming.';
  }

  @override
  String wrongPenalty(String player, int penalty, int cards) {
    String _temp0 = intl.Intl.pluralLogic(
      penalty,
      locale: localeName,
      other: '$penalty swallows',
      one: 'one swallow',
    );
    String _temp1 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: '$cards cards will be removed and redealt.',
      one: 'One card will be removed and redealt.',
    );
    return '$player takes $_temp0. $_temp1';
  }

  @override
  String keepsTurn(String player) {
    return '$player keeps the turn after a wrong guess.';
  }

  @override
  String newGameStarts(String player) {
    return '$player starts a new game.';
  }

  @override
  String roomTitle(String code) {
    return 'Room $code';
  }

  @override
  String browserCopied(String code) {
    return 'Browser address copied. Share it together with room $code.';
  }

  @override
  String playerCount(int count) {
    return 'Players ($count)';
  }

  @override
  String onlineRoom(String code) {
    return 'Online room: $code';
  }

  @override
  String deckCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: 'one card',
    );
    return 'Deck: $_temp0';
  }

  @override
  String suggestion(String move) {
    return 'Suggestion: $move';
  }

  @override
  String valueEstimate(String value) {
    return 'value $value';
  }

  @override
  String remainingDrinks(String value) {
    return 'estimated remaining drinks $value';
  }

  @override
  String changedTotal(int count) {
    return '$count of 17';
  }

  @override
  String chatTitle(String sender) {
    return 'Room chat · $sender';
  }

  @override
  String releaseEmoji(String emoji) {
    return 'Release $emoji for everyone';
  }

  @override
  String deviceLabel(int number, String names) {
    return 'Device $number ($names)';
  }

  @override
  String actionLabel(int row, int column, String orientation, String guess) {
    return 'row $row, column $column: $orientation $guess';
  }

  @override
  String currentBoardOnly(String explanation) {
    return '$explanation (current board only)';
  }

  @override
  String inferenceFailed(String error) {
    return 'ONNX inference failed; using pure statistics. $error';
  }

  @override
  String get cleanupFailed =>
      'Room request cleanup failed; gameplay remains available.';

  @override
  String get handleCard => 'Handle card';

  @override
  String get faceDown => 'Face-down card';

  @override
  String get selectableSuffix => ', selectable';

  @override
  String get suggestedSuffix => ', suggested';

  @override
  String get selectedSuffix => ', selected';

  @override
  String faceUp(String card) {
    return 'Face-up $card';
  }

  @override
  String cardSemantics(
    String face,
    int row,
    int column,
    String legal,
    String proposed,
    String selected,
  ) {
    return '$face, row $row, column $column$legal$proposed$selected';
  }

  @override
  String get defaultPlayer => 'Player 1';

  @override
  String firebaseRequestFailed(int status, String details) {
    return 'Firebase request failed ($status): $details';
  }
}
