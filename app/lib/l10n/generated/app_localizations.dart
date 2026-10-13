import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @choosePlayers.
  ///
  /// In en, this message translates to:
  /// **'Choose player names to begin a local game.'**
  String get choosePlayers;

  /// No description provided for @browserJoinInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter the room code shared by your host and your player names.'**
  String get browserJoinInstructions;

  /// No description provided for @browserUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Browser joining is unavailable: this build has no Firebase configuration.'**
  String get browserUnavailable;

  /// No description provided for @firebaseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Firebase is not configured for this build yet.'**
  String get firebaseUnavailable;

  /// No description provided for @enterPlayer.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one player on this device.'**
  String get enterPlayer;

  /// No description provided for @uniquePlayers.
  ///
  /// In en, this message translates to:
  /// **'Every player sharing this device needs a unique name.'**
  String get uniquePlayers;

  /// No description provided for @validRoomCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the six-character room code shared by your host.'**
  String get validRoomCode;

  /// No description provided for @roomNotFound.
  ///
  /// In en, this message translates to:
  /// **'Room not found. Check the room code.'**
  String get roomNotFound;

  /// No description provided for @waitingAcceptance.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the host to accept your player names…'**
  String get waitingAcceptance;

  /// No description provided for @hostTimeout.
  ///
  /// In en, this message translates to:
  /// **'The host did not respond. Ask them to keep the lobby open, then try again.'**
  String get hostTimeout;

  /// No description provided for @roomUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This room is no longer available.'**
  String get roomUnavailable;

  /// No description provided for @joinInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter a room code and your player names to join.'**
  String get joinInstructions;

  /// No description provided for @chatReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Room chat is reconnecting…'**
  String get chatReconnecting;

  /// No description provided for @sharingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Turn sharing is temporarily unavailable. Gameplay remains available.'**
  String get sharingUnavailable;

  /// No description provided for @openChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChat;

  /// No description provided for @minimizeChat.
  ///
  /// In en, this message translates to:
  /// **'Minimize chat'**
  String get minimizeChat;

  /// No description provided for @chooseComparison.
  ///
  /// In en, this message translates to:
  /// **'Choose the comparison'**
  String get chooseComparison;

  /// No description provided for @horizontalCards.
  ///
  /// In en, this message translates to:
  /// **'Horizontal cards'**
  String get horizontalCards;

  /// No description provided for @verticalCards.
  ///
  /// In en, this message translates to:
  /// **'Vertical cards'**
  String get verticalCards;

  /// No description provided for @betweenOutside.
  ///
  /// In en, this message translates to:
  /// **'In-between or outside'**
  String get betweenOutside;

  /// No description provided for @higherSameLower.
  ///
  /// In en, this message translates to:
  /// **'Higher, same, or lower'**
  String get higherSameLower;

  /// No description provided for @yourGuess.
  ///
  /// In en, this message translates to:
  /// **'Your guess'**
  String get yourGuess;

  /// Guess that the hidden card has a higher rank.
  ///
  /// In en, this message translates to:
  /// **'Higher'**
  String get higher;

  /// Guess that the hidden card has the same rank.
  ///
  /// In en, this message translates to:
  /// **'Same'**
  String get same;

  /// No description provided for @lower.
  ///
  /// In en, this message translates to:
  /// **'Lower'**
  String get lower;

  /// Guess that the hidden rank lies strictly between the two visible ranks.
  ///
  /// In en, this message translates to:
  /// **'In-between'**
  String get inBetween;

  /// No description provided for @outside.
  ///
  /// In en, this message translates to:
  /// **'Outside'**
  String get outside;

  /// No description provided for @bestMovePrediction.
  ///
  /// In en, this message translates to:
  /// **'Best-move prediction'**
  String get bestMovePrediction;

  /// No description provided for @rlModel.
  ///
  /// In en, this message translates to:
  /// **'RL model'**
  String get rlModel;

  /// No description provided for @pureStatistics.
  ///
  /// In en, this message translates to:
  /// **'Pure statistics'**
  String get pureStatistics;

  /// No description provided for @statisticsDescription.
  ///
  /// In en, this message translates to:
  /// **'Estimate your future drinks using public card history.'**
  String get statisticsDescription;

  /// No description provided for @findingMove.
  ///
  /// In en, this message translates to:
  /// **'Finding best move…'**
  String get findingMove;

  /// No description provided for @submittingMove.
  ///
  /// In en, this message translates to:
  /// **'Submitting move…'**
  String get submittingMove;

  /// No description provided for @moveSent.
  ///
  /// In en, this message translates to:
  /// **'Move request sent to host.'**
  String get moveSent;

  /// No description provided for @finishPendingProposal.
  ///
  /// In en, this message translates to:
  /// **'Finish the pending action before requesting a proposal.'**
  String get finishPendingProposal;

  /// No description provided for @startingGame.
  ///
  /// In en, this message translates to:
  /// **'Starting game…'**
  String get startingGame;

  /// No description provided for @cardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That card cannot be selected yet.'**
  String get cardUnavailable;

  /// No description provided for @sameCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct: same rank!'**
  String get sameCorrect;

  /// No description provided for @continueGame.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueGame;

  /// No description provided for @windowComplete.
  ///
  /// In en, this message translates to:
  /// **'The window is complete!'**
  String get windowComplete;

  /// No description provided for @correctContinue.
  ///
  /// In en, this message translates to:
  /// **'Correct. You may guess again or end your turn.'**
  String get correctContinue;

  /// No description provided for @wrongRedeal.
  ///
  /// In en, this message translates to:
  /// **'Wrong guess. The revealed card and every card with a red border will be redealt.'**
  String get wrongRedeal;

  /// No description provided for @wrongGuess.
  ///
  /// In en, this message translates to:
  /// **'Wrong guess'**
  String get wrongGuess;

  /// No description provided for @redealCards.
  ///
  /// In en, this message translates to:
  /// **'Redeal cards'**
  String get redealCards;

  /// No description provided for @joinWindow.
  ///
  /// In en, this message translates to:
  /// **'Join Window'**
  String get joinWindow;

  /// No description provided for @browserDescription.
  ///
  /// In en, this message translates to:
  /// **'Play with friends, directly in your browser. No installation required.'**
  String get browserDescription;

  /// No description provided for @askHost.
  ///
  /// In en, this message translates to:
  /// **'Ask your host to create a lobby in the smartphone or PC/laptop app and share its room code.'**
  String get askHost;

  /// No description provided for @roomCode.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get roomCode;

  /// No description provided for @devicePlayers.
  ///
  /// In en, this message translates to:
  /// **'Players on this device'**
  String get devicePlayers;

  /// No description provided for @namesHelper.
  ///
  /// In en, this message translates to:
  /// **'One or more names, separated by commas.'**
  String get namesHelper;

  /// No description provided for @separateNames.
  ///
  /// In en, this message translates to:
  /// **'Separate names with commas.'**
  String get separateNames;

  /// No description provided for @joining.
  ///
  /// In en, this message translates to:
  /// **'Joining…'**
  String get joining;

  /// No description provided for @joinOnline.
  ///
  /// In en, this message translates to:
  /// **'Join online room'**
  String get joinOnline;

  /// No description provided for @localDescription.
  ///
  /// In en, this message translates to:
  /// **'A local, cross-platform edition of the German card game.'**
  String get localDescription;

  /// No description provided for @players.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get players;

  /// No description provided for @startLocal.
  ///
  /// In en, this message translates to:
  /// **'Start local game'**
  String get startLocal;

  /// No description provided for @createLobby.
  ///
  /// In en, this message translates to:
  /// **'Create online lobby'**
  String get createLobby;

  /// No description provided for @firebaseSetupNeeded.
  ///
  /// In en, this message translates to:
  /// **'Online rooms need Firebase setup'**
  String get firebaseSetupNeeded;

  /// No description provided for @windowLobby.
  ///
  /// In en, this message translates to:
  /// **'Window lobby'**
  String get windowLobby;

  /// No description provided for @leaveLobby.
  ///
  /// In en, this message translates to:
  /// **'Leave lobby and return to menu'**
  String get leaveLobby;

  /// No description provided for @shareCode.
  ///
  /// In en, this message translates to:
  /// **'Share this code. Players may join until you start the game.'**
  String get shareCode;

  /// No description provided for @waitingStart.
  ///
  /// In en, this message translates to:
  /// **'You are in the lobby. Waiting for the host to start.'**
  String get waitingStart;

  /// No description provided for @friendsJoin.
  ///
  /// In en, this message translates to:
  /// **'Friends can join in the app with this room code, or in their browser at:'**
  String get friendsJoin;

  /// No description provided for @browserCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Browser players enter the room code above. No installation required.'**
  String get browserCodeHelp;

  /// No description provided for @copyBrowser.
  ///
  /// In en, this message translates to:
  /// **'Copy browser address'**
  String get copyBrowser;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @startLockLobby.
  ///
  /// In en, this message translates to:
  /// **'Start game and lock lobby'**
  String get startLockLobby;

  /// No description provided for @leaveRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave room and return to menu'**
  String get leaveRoom;

  /// No description provided for @returnMenu.
  ///
  /// In en, this message translates to:
  /// **'Return to menu'**
  String get returnMenu;

  /// No description provided for @currentPlayer.
  ///
  /// In en, this message translates to:
  /// **'Current player'**
  String get currentPlayer;

  /// No description provided for @newLocal.
  ///
  /// In en, this message translates to:
  /// **'New local game'**
  String get newLocal;

  /// No description provided for @waitingPlayer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the player who owns this seat.'**
  String get waitingPlayer;

  /// No description provided for @handleRule.
  ///
  /// In en, this message translates to:
  /// **'Handle rule: choose a card directly beside the handle.'**
  String get handleRule;

  /// No description provided for @hostDeck.
  ///
  /// In en, this message translates to:
  /// **'Deck: managed by host'**
  String get hostDeck;

  /// No description provided for @endTurn.
  ///
  /// In en, this message translates to:
  /// **'End turn'**
  String get endTurn;

  /// No description provided for @endTurnSuggested.
  ///
  /// In en, this message translates to:
  /// **'End turn · suggested'**
  String get endTurnSuggested;

  /// No description provided for @confirmSame.
  ///
  /// In en, this message translates to:
  /// **'Confirm same-rank penalty'**
  String get confirmSame;

  /// No description provided for @redealMarked.
  ///
  /// In en, this message translates to:
  /// **'Redeal marked cards'**
  String get redealMarked;

  /// No description provided for @proposeMove.
  ///
  /// In en, this message translates to:
  /// **'Propose best move'**
  String get proposeMove;

  /// No description provided for @scoreboard.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard'**
  String get scoreboard;

  /// No description provided for @player.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get player;

  /// No description provided for @drinks.
  ///
  /// In en, this message translates to:
  /// **'Drinks'**
  String get drinks;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get correct;

  /// No description provided for @wrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get wrong;

  /// No description provided for @ratio.
  ///
  /// In en, this message translates to:
  /// **'C/W ratio'**
  String get ratio;

  /// No description provided for @changed.
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get changed;

  /// No description provided for @turns.
  ///
  /// In en, this message translates to:
  /// **'Turns'**
  String get turns;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @sayHello.
  ///
  /// In en, this message translates to:
  /// **'Say hello to your room!'**
  String get sayHello;

  /// No description provided for @enableReactions.
  ///
  /// In en, this message translates to:
  /// **'Enable flying reactions'**
  String get enableReactions;

  /// No description provided for @reduceReactions.
  ///
  /// In en, this message translates to:
  /// **'Reduce reaction animations'**
  String get reduceReactions;

  /// No description provided for @collapseHistory.
  ///
  /// In en, this message translates to:
  /// **'Collapse chat history'**
  String get collapseHistory;

  /// No description provided for @expandHistory.
  ///
  /// In en, this message translates to:
  /// **'Expand chat history'**
  String get expandHistory;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message everyone…'**
  String get messageHint;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// No description provided for @waitMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment before sending another message.'**
  String get waitMessage;

  /// No description provided for @messageFailed.
  ///
  /// In en, this message translates to:
  /// **'Message could not be sent. Please retry.'**
  String get messageFailed;

  /// No description provided for @reactionFailed.
  ///
  /// In en, this message translates to:
  /// **'Reaction could not be sent. Please retry.'**
  String get reactionFailed;

  /// No description provided for @modelLoaded.
  ///
  /// In en, this message translates to:
  /// **'ONNX policy loaded.'**
  String get modelLoaded;

  /// No description provided for @testModelLoaded.
  ///
  /// In en, this message translates to:
  /// **'ONNX test model loaded.'**
  String get testModelLoaded;

  /// No description provided for @modelWillLoad.
  ///
  /// In en, this message translates to:
  /// **'Bundled ONNX model will load when you request a proposal.'**
  String get modelWillLoad;

  /// No description provided for @modelLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading bundled ONNX model…'**
  String get modelLoading;

  /// No description provided for @modelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'RL model unavailable.'**
  String get modelUnavailable;

  /// No description provided for @modelSource.
  ///
  /// In en, this message translates to:
  /// **'ONNX policy'**
  String get modelSource;

  /// No description provided for @testModelSource.
  ///
  /// In en, this message translates to:
  /// **'ONNX test model (untrained)'**
  String get testModelSource;

  /// No description provided for @passAction.
  ///
  /// In en, this message translates to:
  /// **'end turn (pass)'**
  String get passAction;

  /// No description provided for @horizontal.
  ///
  /// In en, this message translates to:
  /// **'horizontal'**
  String get horizontal;

  /// No description provided for @vertical.
  ///
  /// In en, this message translates to:
  /// **'vertical'**
  String get vertical;

  /// No description provided for @noImmediateDrinks.
  ///
  /// In en, this message translates to:
  /// **'no immediate drinks'**
  String get noImmediateDrinks;

  /// No description provided for @estimatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'estimated success'**
  String get estimatedSuccess;

  /// No description provided for @modelConfidence.
  ///
  /// In en, this message translates to:
  /// **'model confidence'**
  String get modelConfidence;

  /// No description provided for @passExplanation.
  ///
  /// In en, this message translates to:
  /// **'Pass to avoid more risk'**
  String get passExplanation;

  /// No description provided for @certainExplanation.
  ///
  /// In en, this message translates to:
  /// **'Certain guess, no immediate drinks'**
  String get certainExplanation;

  /// No description provided for @smallPenaltyExplanation.
  ///
  /// In en, this message translates to:
  /// **'Low risk, small penalty'**
  String get smallPenaltyExplanation;

  /// No description provided for @futureDrinksExplanation.
  ///
  /// In en, this message translates to:
  /// **'Lower expected future drinks'**
  String get futureDrinksExplanation;

  /// No description provided for @strongOddsExplanation.
  ///
  /// In en, this message translates to:
  /// **'Strong odds, lower future risk'**
  String get strongOddsExplanation;

  /// No description provided for @pendingAction.
  ///
  /// In en, this message translates to:
  /// **'Finish the pending action first.'**
  String get pendingAction;

  /// No description provided for @invalidSelection.
  ///
  /// In en, this message translates to:
  /// **'Invalid card selection.'**
  String get invalidSelection;

  /// No description provided for @invalidGuess.
  ///
  /// In en, this message translates to:
  /// **'Invalid guess.'**
  String get invalidGuess;

  /// No description provided for @noSamePending.
  ///
  /// In en, this message translates to:
  /// **'No same guess is pending.'**
  String get noSamePending;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one player name.'**
  String get enterName;

  /// No description provided for @uniqueDeviceNames.
  ///
  /// In en, this message translates to:
  /// **'Every player on this device needs a unique name.'**
  String get uniqueDeviceNames;

  /// No description provided for @gameAlreadyStarted.
  ///
  /// In en, this message translates to:
  /// **'This game has already started. Ask the host for a new lobby.'**
  String get gameAlreadyStarted;

  /// No description provided for @deviceAlreadyJoined.
  ///
  /// In en, this message translates to:
  /// **'This device has already joined the lobby.'**
  String get deviceAlreadyJoined;

  /// No description provided for @uniqueLobbyNames.
  ///
  /// In en, this message translates to:
  /// **'Player names must be unique in the lobby. Choose other names.'**
  String get uniqueLobbyNames;

  /// No description provided for @rejoinRoom.
  ///
  /// In en, this message translates to:
  /// **'Please rejoin the room.'**
  String get rejoinRoom;

  /// No description provided for @signInExpired.
  ///
  /// In en, this message translates to:
  /// **'Firebase sign-in expired. Please rejoin.'**
  String get signInExpired;

  /// No description provided for @reserveRoomFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reserve a room code. Please try again.'**
  String get reserveRoomFailed;

  /// No description provided for @playerStarts.
  ///
  /// In en, this message translates to:
  /// **'{player} starts. Select a card next to the handle.'**
  String playerStarts(String player);

  /// No description provided for @roomTurn.
  ///
  /// In en, this message translates to:
  /// **'Room {code}: {player}\'s turn.'**
  String roomTurn(String code, String player);

  /// No description provided for @playerTurn.
  ///
  /// In en, this message translates to:
  /// **'{player}\'s turn.'**
  String playerTurn(String player);

  /// No description provided for @lobbyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Lobby {code}: waiting for the host to start.'**
  String lobbyWaiting(String code);

  /// No description provided for @restoringHost.
  ///
  /// In en, this message translates to:
  /// **'Restoring host state for room {code}…'**
  String restoringHost(String code);

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create room: {error}'**
  String createFailed(String error);

  /// No description provided for @joinFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not join room: {error}'**
  String joinFailed(String error);

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Room connection failed: {error}'**
  String connectionFailed(String error);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'The host state could not be restored: {error}'**
  String restoreFailed(String error);

  /// No description provided for @moveRejected.
  ///
  /// In en, this message translates to:
  /// **'Move rejected: {error}'**
  String moveRejected(String error);

  /// No description provided for @predictionFailed.
  ///
  /// In en, this message translates to:
  /// **'Prediction failed: {error}'**
  String predictionFailed(String error);

  /// No description provided for @startFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the lobby: {error}'**
  String startFailed(String error);

  /// No description provided for @requestFailed.
  ///
  /// In en, this message translates to:
  /// **'Room request failed: {error}'**
  String requestFailed(String error);

  /// No description provided for @hostRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Room host request error: {error}'**
  String hostRequestFailed(String error);

  /// No description provided for @invalidRequest.
  ///
  /// In en, this message translates to:
  /// **'Ignored invalid room request: {error}'**
  String invalidRequest(String error);

  /// No description provided for @suggestedMove.
  ///
  /// In en, this message translates to:
  /// **'Suggested move: {move}.'**
  String suggestedMove(String move);

  /// No description provided for @suggestedGuess.
  ///
  /// In en, this message translates to:
  /// **'{guess} · suggested'**
  String suggestedGuess(String guess);

  /// No description provided for @watchingPlayer.
  ///
  /// In en, this message translates to:
  /// **'Watching {player}'**
  String watchingPlayer(String player);

  /// No description provided for @samePenalty.
  ///
  /// In en, this message translates to:
  /// **'Every other player takes one swallow. {player} can continue after confirming.'**
  String samePenalty(String player);

  /// No description provided for @wrongPenalty.
  ///
  /// In en, this message translates to:
  /// **'{player} takes {penalty, plural, =1{one swallow} other{{penalty} swallows}}. {cards, plural, =1{One card will be removed and redealt.} other{{cards} cards will be removed and redealt.}}'**
  String wrongPenalty(String player, int penalty, int cards);

  /// No description provided for @keepsTurn.
  ///
  /// In en, this message translates to:
  /// **'{player} keeps the turn after a wrong guess.'**
  String keepsTurn(String player);

  /// No description provided for @newGameStarts.
  ///
  /// In en, this message translates to:
  /// **'{player} starts a new game.'**
  String newGameStarts(String player);

  /// No description provided for @roomTitle.
  ///
  /// In en, this message translates to:
  /// **'Room {code}'**
  String roomTitle(String code);

  /// No description provided for @browserCopied.
  ///
  /// In en, this message translates to:
  /// **'Browser address copied. Share it together with room {code}.'**
  String browserCopied(String code);

  /// No description provided for @playerCount.
  ///
  /// In en, this message translates to:
  /// **'Players ({count})'**
  String playerCount(int count);

  /// No description provided for @onlineRoom.
  ///
  /// In en, this message translates to:
  /// **'Online room: {code}'**
  String onlineRoom(String code);

  /// No description provided for @deckCards.
  ///
  /// In en, this message translates to:
  /// **'Deck: {count, plural, =1{one card} other{{count} cards}}'**
  String deckCards(int count);

  /// No description provided for @suggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion: {move}'**
  String suggestion(String move);

  /// No description provided for @valueEstimate.
  ///
  /// In en, this message translates to:
  /// **'value {value}'**
  String valueEstimate(String value);

  /// No description provided for @remainingDrinks.
  ///
  /// In en, this message translates to:
  /// **'estimated remaining drinks {value}'**
  String remainingDrinks(String value);

  /// No description provided for @changedTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} of 17'**
  String changedTotal(int count);

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Room chat · {sender}'**
  String chatTitle(String sender);

  /// No description provided for @releaseEmoji.
  ///
  /// In en, this message translates to:
  /// **'Release {emoji} for everyone'**
  String releaseEmoji(String emoji);

  /// No description provided for @deviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Device {number} ({names})'**
  String deviceLabel(int number, String names);

  /// No description provided for @actionLabel.
  ///
  /// In en, this message translates to:
  /// **'row {row}, column {column}: {orientation} {guess}'**
  String actionLabel(int row, int column, String orientation, String guess);

  /// No description provided for @currentBoardOnly.
  ///
  /// In en, this message translates to:
  /// **'{explanation} (current board only)'**
  String currentBoardOnly(String explanation);

  /// No description provided for @inferenceFailed.
  ///
  /// In en, this message translates to:
  /// **'RL adviser unavailable: {error}'**
  String inferenceFailed(String error);

  /// No description provided for @cleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Room request cleanup failed; gameplay remains available.'**
  String get cleanupFailed;

  /// No description provided for @handleCard.
  ///
  /// In en, this message translates to:
  /// **'Handle card'**
  String get handleCard;

  /// No description provided for @faceDown.
  ///
  /// In en, this message translates to:
  /// **'Face-down card'**
  String get faceDown;

  /// No description provided for @selectableSuffix.
  ///
  /// In en, this message translates to:
  /// **', selectable'**
  String get selectableSuffix;

  /// No description provided for @suggestedSuffix.
  ///
  /// In en, this message translates to:
  /// **', suggested'**
  String get suggestedSuffix;

  /// No description provided for @selectedSuffix.
  ///
  /// In en, this message translates to:
  /// **', selected'**
  String get selectedSuffix;

  /// No description provided for @faceUp.
  ///
  /// In en, this message translates to:
  /// **'Face-up {card}'**
  String faceUp(String card);

  /// No description provided for @cardSemantics.
  ///
  /// In en, this message translates to:
  /// **'{face}, row {row}, column {column}{legal}{proposed}{selected}'**
  String cardSemantics(
    String face,
    int row,
    int column,
    String legal,
    String proposed,
    String selected,
  );

  /// No description provided for @defaultPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player 1'**
  String get defaultPlayer;

  /// No description provided for @firebaseRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Firebase request failed ({status}): {details}'**
  String firebaseRequestFailed(int status, String details);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
