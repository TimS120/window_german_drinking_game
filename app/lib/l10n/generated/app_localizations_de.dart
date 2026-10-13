// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Window';

  @override
  String get language => 'Sprache';

  @override
  String get chooseLanguage => 'Sprache wählen';

  @override
  String get choosePlayers =>
      'Gib die Spielernamen ein, um ein lokales Spiel zu starten.';

  @override
  String get browserJoinInstructions =>
      'Gib den Raumcode des Gastgebers und eure Spielernamen ein.';

  @override
  String get browserUnavailable =>
      'Der Beitritt im Browser ist nicht verfügbar: Firebase ist für diese Version nicht eingerichtet.';

  @override
  String get firebaseUnavailable =>
      'Firebase ist für diese Version noch nicht eingerichtet.';

  @override
  String get enterPlayer =>
      'Gib mindestens einen Spieler auf diesem Gerät ein.';

  @override
  String get uniquePlayers =>
      'Jeder Spieler auf diesem Gerät braucht einen eindeutigen Namen.';

  @override
  String get validRoomCode =>
      'Gib den sechsstelligen Raumcode des Gastgebers ein.';

  @override
  String get roomNotFound => 'Raum nicht gefunden. Prüfe den Raumcode.';

  @override
  String get waitingAcceptance =>
      'Warte auf die Bestätigung eurer Spielernamen durch den Gastgeber…';

  @override
  String get hostTimeout =>
      'Der Gastgeber antwortet nicht. Bitte ihn, die Lobby geöffnet zu lassen, und versuche es erneut.';

  @override
  String get roomUnavailable => 'Dieser Raum ist nicht mehr verfügbar.';

  @override
  String get joinInstructions =>
      'Gib einen Raumcode und eure Spielernamen ein, um beizutreten.';

  @override
  String get chatReconnecting =>
      'Die Verbindung zum Raumchat wird wiederhergestellt…';

  @override
  String get sharingUnavailable =>
      'Die Zugansicht ist vorübergehend nicht verfügbar. Du kannst weiterhin spielen.';

  @override
  String get openChat => 'Chat öffnen';

  @override
  String get minimizeChat => 'Chat minimieren';

  @override
  String get chooseComparison => 'Vergleich wählen';

  @override
  String get horizontalCards => 'Waagerechte Karten';

  @override
  String get verticalCards => 'Senkrechte Karten';

  @override
  String get betweenOutside => 'Dazwischen oder außerhalb';

  @override
  String get higherSameLower => 'Höher, gleich oder niedriger';

  @override
  String get yourGuess => 'Dein Tipp';

  @override
  String get higher => 'Höher';

  @override
  String get same => 'Gleich';

  @override
  String get lower => 'Niedriger';

  @override
  String get inBetween => 'Dazwischen';

  @override
  String get outside => 'Außerhalb';

  @override
  String get bestMovePrediction => 'Zugempfehlung';

  @override
  String get rlModel => 'RL-Modell';

  @override
  String get pureStatistics => 'Reine Statistik';

  @override
  String get statisticsDescription =>
      'Schätze deine künftigen Schlucke anhand der bekannten Kartenhistorie.';

  @override
  String get findingMove => 'Suche den besten Zug…';

  @override
  String get submittingMove => 'Zug wird übermittelt…';

  @override
  String get moveSent => 'Zuganfrage an den Gastgeber gesendet.';

  @override
  String get finishPendingProposal =>
      'Schließe die laufende Aktion ab, bevor du eine Empfehlung anforderst.';

  @override
  String get startingGame => 'Spiel wird gestartet…';

  @override
  String get cardUnavailable => 'Diese Karte kann noch nicht gewählt werden.';

  @override
  String get sameCorrect => 'Richtig: gleicher Kartenwert!';

  @override
  String get continueGame => 'Weiter';

  @override
  String get windowComplete => 'Das Fenster ist vollständig!';

  @override
  String get correctContinue =>
      'Richtig. Du kannst erneut tippen oder deinen Zug beenden.';

  @override
  String get wrongRedeal =>
      'Falscher Tipp. Die aufgedeckte Karte und alle rot umrandeten Karten werden neu verteilt.';

  @override
  String get wrongGuess => 'Falscher Tipp';

  @override
  String get redealCards => 'Karten neu verteilen';

  @override
  String get joinWindow => 'Window beitreten';

  @override
  String get browserDescription =>
      'Spiele mit Freunden direkt im Browser. Keine Installation nötig.';

  @override
  String get askHost =>
      'Bitte den Gastgeber, in der Smartphone- oder PC-App eine Lobby zu erstellen und den Raumcode zu teilen.';

  @override
  String get roomCode => 'Raumcode';

  @override
  String get devicePlayers => 'Spieler auf diesem Gerät';

  @override
  String get namesHelper => 'Ein oder mehrere Namen, durch Kommas getrennt.';

  @override
  String get separateNames => 'Trenne die Namen mit Kommas.';

  @override
  String get joining => 'Beitritt läuft…';

  @override
  String get joinOnline => 'Online-Raum beitreten';

  @override
  String get localDescription =>
      'Eine plattformübergreifende Version des deutschen Kartenspiels.';

  @override
  String get players => 'Spieler';

  @override
  String get startLocal => 'Lokales Spiel starten';

  @override
  String get createLobby => 'Online-Lobby erstellen';

  @override
  String get firebaseSetupNeeded =>
      'Online-Räume benötigen eine Firebase-Einrichtung';

  @override
  String get windowLobby => 'Window-Lobby';

  @override
  String get leaveLobby => 'Lobby verlassen und zum Menü zurückkehren';

  @override
  String get shareCode =>
      'Teile diesen Code. Spieler können beitreten, bis du das Spiel startest.';

  @override
  String get waitingStart =>
      'Du bist in der Lobby. Warte auf den Spielstart durch den Gastgeber.';

  @override
  String get friendsJoin =>
      'Freunde können mit diesem Raumcode in der App oder im Browser unter folgender Adresse beitreten:';

  @override
  String get browserCodeHelp =>
      'Spieler im Browser geben den Raumcode von oben ein. Keine Installation nötig.';

  @override
  String get copyBrowser => 'Browseradresse kopieren';

  @override
  String get host => 'Gastgeber';

  @override
  String get startLockLobby => 'Spiel starten und Lobby schließen';

  @override
  String get leaveRoom => 'Raum verlassen und zum Menü zurückkehren';

  @override
  String get returnMenu => 'Zum Menü zurückkehren';

  @override
  String get currentPlayer => 'Aktueller Spieler';

  @override
  String get newLocal => 'Neues lokales Spiel';

  @override
  String get waitingPlayer => 'Warte auf den Spieler, der gerade am Zug ist.';

  @override
  String get handleRule =>
      'Griffregel: Wähle eine Karte direkt neben dem Griff.';

  @override
  String get hostDeck => 'Stapel: vom Gastgeber verwaltet';

  @override
  String get endTurn => 'Zug beenden';

  @override
  String get endTurnSuggested => 'Zug beenden · empfohlen';

  @override
  String get confirmSame => 'Schlucke bei gleichem Kartenwert bestätigen';

  @override
  String get redealMarked => 'Markierte Karten neu verteilen';

  @override
  String get proposeMove => 'Besten Zug vorschlagen';

  @override
  String get scoreboard => 'Spielstatistik';

  @override
  String get player => 'Spieler';

  @override
  String get drinks => 'Schlucke';

  @override
  String get correct => 'Richtig';

  @override
  String get wrong => 'Falsch';

  @override
  String get ratio => 'R/F-Verhältnis';

  @override
  String get changed => 'Gewechselt';

  @override
  String get turns => 'Züge';

  @override
  String get total => 'Gesamt';

  @override
  String get sayHello => 'Sag deinem Raum Hallo!';

  @override
  String get enableReactions => 'Fliegende Reaktionen aktivieren';

  @override
  String get reduceReactions => 'Reaktionsanimationen reduzieren';

  @override
  String get collapseHistory => 'Chatverlauf verkleinern';

  @override
  String get expandHistory => 'Chatverlauf vergrößern';

  @override
  String get messageHint => 'Nachricht an alle…';

  @override
  String get sendMessage => 'Nachricht senden';

  @override
  String get waitMessage =>
      'Bitte warte einen Moment, bevor du die nächste Nachricht sendest.';

  @override
  String get messageFailed =>
      'Die Nachricht konnte nicht gesendet werden. Bitte versuche es erneut.';

  @override
  String get reactionFailed =>
      'Die Reaktion konnte nicht gesendet werden. Bitte versuche es erneut.';

  @override
  String get modelLoaded => 'ONNX-Modell geladen.';

  @override
  String get testModelLoaded => 'ONNX-Testmodell geladen.';

  @override
  String get modelWillLoad =>
      'Das enthaltene ONNX-Testmodell wird geladen, sobald du eine Empfehlung anforderst.';

  @override
  String get modelLoading => 'Enthaltenes ONNX-Modell wird geladen…';

  @override
  String get modelUnavailable =>
      'Modell nicht verfügbar; stattdessen wird reine Statistik verwendet.';

  @override
  String get modelSource => 'ONNX-Modell';

  @override
  String get testModelSource => 'ONNX-Testmodell (untrainiert)';

  @override
  String get fallbackSource =>
      'ONNX-Auswertung fehlgeschlagen → Reine Statistik';

  @override
  String get passAction => 'Zug beenden (passen)';

  @override
  String get horizontal => 'waagerecht';

  @override
  String get vertical => 'senkrecht';

  @override
  String get noImmediateDrinks => 'keine unmittelbaren Schlucke';

  @override
  String get estimatedSuccess => 'geschätzte Erfolgschance';

  @override
  String get modelConfidence => 'Modellsicherheit';

  @override
  String get passExplanation => 'Passen, um weiteres Risiko zu vermeiden';

  @override
  String get certainExplanation =>
      'Sicherer Tipp, keine unmittelbaren Schlucke';

  @override
  String get smallPenaltyExplanation => 'Geringes Risiko, wenige Strafschlucke';

  @override
  String get futureDrinksExplanation => 'Weniger erwartete künftige Schlucke';

  @override
  String get strongOddsExplanation =>
      'Gute Erfolgschance, geringeres künftiges Risiko';

  @override
  String get pendingAction => 'Schließe zuerst die laufende Aktion ab.';

  @override
  String get invalidSelection => 'Ungültige Kartenauswahl.';

  @override
  String get invalidGuess => 'Ungültiger Tipp.';

  @override
  String get noSamePending =>
      'Es wartet keine Bestätigung eines Tipps auf gleichen Kartenwert.';

  @override
  String get enterName => 'Gib mindestens einen Spielernamen ein.';

  @override
  String get uniqueDeviceNames =>
      'Jeder Spieler auf diesem Gerät braucht einen eindeutigen Namen.';

  @override
  String get gameAlreadyStarted =>
      'Dieses Spiel hat bereits begonnen. Bitte den Gastgeber um eine neue Lobby.';

  @override
  String get deviceAlreadyJoined =>
      'Dieses Gerät ist der Lobby bereits beigetreten.';

  @override
  String get uniqueLobbyNames =>
      'Die Spielernamen müssen in der Lobby eindeutig sein. Wähle andere Namen.';

  @override
  String get rejoinRoom => 'Bitte tritt dem Raum erneut bei.';

  @override
  String get signInExpired =>
      'Die Firebase-Anmeldung ist abgelaufen. Bitte tritt erneut bei.';

  @override
  String get reserveRoomFailed =>
      'Es konnte kein Raumcode reserviert werden. Bitte versuche es erneut.';

  @override
  String playerStarts(String player) {
    return '$player beginnt. Wähle eine Karte neben dem Griff.';
  }

  @override
  String roomTurn(String code, String player) {
    return 'Raum $code: $player ist am Zug.';
  }

  @override
  String playerTurn(String player) {
    return '$player ist am Zug.';
  }

  @override
  String lobbyWaiting(String code) {
    return 'Lobby $code: Warte auf den Spielstart durch den Gastgeber.';
  }

  @override
  String restoringHost(String code) {
    return 'Spielstand des Gastgebers für Raum $code wird wiederhergestellt…';
  }

  @override
  String createFailed(String error) {
    return 'Raum konnte nicht erstellt werden: $error';
  }

  @override
  String joinFailed(String error) {
    return 'Raumbeitritt fehlgeschlagen: $error';
  }

  @override
  String connectionFailed(String error) {
    return 'Verbindung zum Raum fehlgeschlagen: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Spielstand des Gastgebers konnte nicht wiederhergestellt werden: $error';
  }

  @override
  String moveRejected(String error) {
    return 'Zug abgelehnt: $error';
  }

  @override
  String predictionFailed(String error) {
    return 'Zugempfehlung fehlgeschlagen: $error';
  }

  @override
  String startFailed(String error) {
    return 'Lobby konnte nicht gestartet werden: $error';
  }

  @override
  String requestFailed(String error) {
    return 'Raumanfrage fehlgeschlagen: $error';
  }

  @override
  String hostRequestFailed(String error) {
    return 'Fehler bei einer Anfrage an den Gastgeber: $error';
  }

  @override
  String invalidRequest(String error) {
    return 'Ungültige Raumanfrage ignoriert: $error';
  }

  @override
  String suggestedMove(String move) {
    return 'Empfohlener Zug: $move.';
  }

  @override
  String suggestedGuess(String guess) {
    return '$guess · empfohlen';
  }

  @override
  String watchingPlayer(String player) {
    return 'Zugansicht von $player';
  }

  @override
  String samePenalty(String player) {
    return 'Alle anderen Spieler trinken einen Schluck. $player kann nach der Bestätigung weiterspielen.';
  }

  @override
  String wrongPenalty(String player, int penalty, int cards) {
    String _temp0 = intl.Intl.pluralLogic(
      penalty,
      locale: localeName,
      other: '$penalty Schlucke',
      one: 'einen Schluck',
    );
    String _temp1 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: '$cards Karten werden entfernt und neu verteilt.',
      one: 'Eine Karte wird entfernt und neu verteilt.',
    );
    return '$player trinkt $_temp0. $_temp1';
  }

  @override
  String keepsTurn(String player) {
    return '$player bleibt nach einem falschen Tipp am Zug.';
  }

  @override
  String newGameStarts(String player) {
    return '$player beginnt ein neues Spiel.';
  }

  @override
  String roomTitle(String code) {
    return 'Raum $code';
  }

  @override
  String browserCopied(String code) {
    return 'Browseradresse kopiert. Teile sie zusammen mit dem Code für Raum $code.';
  }

  @override
  String playerCount(int count) {
    return 'Spieler ($count)';
  }

  @override
  String onlineRoom(String code) {
    return 'Online-Raum: $code';
  }

  @override
  String deckCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten',
      one: 'eine Karte',
    );
    return 'Stapel: $_temp0';
  }

  @override
  String suggestion(String move) {
    return 'Empfehlung: $move';
  }

  @override
  String valueEstimate(String value) {
    return 'Wert $value';
  }

  @override
  String remainingDrinks(String value) {
    return 'geschätzte verbleibende Schlucke $value';
  }

  @override
  String changedTotal(int count) {
    return '$count von 17';
  }

  @override
  String chatTitle(String sender) {
    return 'Raumchat · $sender';
  }

  @override
  String releaseEmoji(String emoji) {
    return '$emoji für alle loslassen';
  }

  @override
  String deviceLabel(int number, String names) {
    return 'Gerät $number ($names)';
  }

  @override
  String actionLabel(int row, int column, String orientation, String guess) {
    return 'Zeile $row, Spalte $column: $orientation $guess';
  }

  @override
  String currentBoardOnly(String explanation) {
    return '$explanation (nur aktuelles Spielfeld)';
  }

  @override
  String inferenceFailed(String error) {
    return 'ONNX-Auswertung fehlgeschlagen; stattdessen wird reine Statistik verwendet. $error';
  }

  @override
  String get cleanupFailed =>
      'Das Aufräumen einer Raumanfrage ist fehlgeschlagen. Du kannst weiterhin spielen.';

  @override
  String get handleCard => 'Griffkarte';

  @override
  String get faceDown => 'Verdeckte Karte';

  @override
  String get selectableSuffix => ', auswählbar';

  @override
  String get suggestedSuffix => ', empfohlen';

  @override
  String get selectedSuffix => ', ausgewählt';

  @override
  String faceUp(String card) {
    return 'Aufgedeckte Karte $card';
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
    return '$face, Zeile $row, Spalte $column$legal$proposed$selected';
  }

  @override
  String get defaultPlayer => 'Spieler 1';

  @override
  String firebaseRequestFailed(int status, String details) {
    return 'Firebase-Anfrage fehlgeschlagen ($status): $details';
  }
}
