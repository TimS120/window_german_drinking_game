package window_german_drinking_game.com

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
import window_german_drinking_game.com.game.GameSnapshot
import window_german_drinking_game.com.game.FirebaseRoomRepository
import window_german_drinking_game.com.game.GuessOption
import window_german_drinking_game.com.game.GuessType
import window_german_drinking_game.com.game.Position
import window_german_drinking_game.com.game.WindowGameEngine
import window_german_drinking_game.com.ui.theme.Window_german_drinking_gameTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            Window_german_drinking_gameTheme {
                AppRoot()
            }
        }
    }
}

@Composable
private fun AppRoot() {
    val context = LocalContext.current
    val roomRepository = remember { FirebaseRoomRepository(context) }
    var gameEngine by remember { mutableStateOf<WindowGameEngine?>(null) }
    var snapshot by remember { mutableStateOf<GameSnapshot?>(null) }
    var infoMessage by remember { mutableStateOf("Enter player names to start") }
    var isConnecting by remember { mutableStateOf(false) }
    var roomCode by remember { mutableStateOf<String?>(null) }
    var localPlayerName by remember { mutableStateOf<String?>(null) }
    var remoteVersion by remember { mutableStateOf(0L) }

    var optionDialogTarget by remember { mutableStateOf<Position?>(null) }
    var optionDialogOptions by remember { mutableStateOf<List<GuessOption>>(emptyList()) }

    var guessDialogTarget by remember { mutableStateOf<Position?>(null) }
    var guessDialogOption by remember { mutableStateOf<GuessOption?>(null) }

    var sameConfirmTarget by remember { mutableStateOf<Position?>(null) }
    var removalConfirmVisible by remember { mutableStateOf(false) }
    var resetConfirmVisible by remember { mutableStateOf(false) }
    var endDialogVisible by remember { mutableStateOf(false) }

    fun pushState() {
        val engine = gameEngine ?: return
        val code = roomCode ?: return
        val nextVersion = remoteVersion + 1
        remoteVersion = nextVersion
        roomRepository.writeState(
            roomCode = code,
            state = engine.exportState(version = nextVersion),
            onError = { error -> infoMessage = error },
        )
    }

    fun refresh(pushOnlineState: Boolean = false) {
        snapshot = gameEngine?.snapshot()
        if (snapshot?.gameEnded == true) {
            endDialogVisible = true
        }
        if (pushOnlineState) {
            pushState()
        }
    }

    DisposableEffect(roomCode) {
        val code = roomCode
        if (code == null) {
            onDispose { }
        } else {
            val stopObserving = roomRepository.observeRoom(
                roomCode = code,
                onState = { state ->
                    if (state.version < remoteVersion) return@observeRoom
                    remoteVersion = state.version
                    if (gameEngine == null || gameEngine?.players != state.players) {
                        gameEngine = WindowGameEngine(state.players)
                    }
                    gameEngine?.restoreState(state)
                    snapshot = gameEngine?.snapshot()
                    infoMessage = "Room $code connected. ${state.players.getOrNull(state.currentPlayerIdx)}'s turn"
                },
                onError = { error -> infoMessage = error },
            )
            onDispose { stopObserving() }
        }
    }

    if (gameEngine == null || snapshot == null) {
        PlayerSetupScreen(
            onStartOffline = { players ->
                isConnecting = false
                roomCode = null
                localPlayerName = null
                remoteVersion = 0
                gameEngine = WindowGameEngine(players)
                snapshot = gameEngine!!.snapshot()
                infoMessage = "${snapshot!!.currentPlayer}'s turn"
            },
            onCreateRoom = { players, localName ->
                isConnecting = true
                infoMessage = "Signing in to Firebase..."
                roomRepository.signInAnonymously(
                    onSuccess = {
                        infoMessage = "Creating room..."
                        val engine = WindowGameEngine(players)
                        roomRepository.createRoom(
                            initialState = engine.exportState(version = 1),
                            onSuccess = { createdCode ->
                                gameEngine = engine
                                snapshot = engine.snapshot()
                                roomCode = createdCode
                                localPlayerName = localName
                                remoteVersion = 1
                                isConnecting = false
                                infoMessage = "Room $createdCode created. ${engine.currentPlayer()}'s turn"
                            },
                            onError = { error ->
                                isConnecting = false
                                infoMessage = error
                            },
                        )
                    },
                    onError = { error ->
                        isConnecting = false
                        infoMessage = error
                    },
                )
            },
            onJoinRoom = { code, localName ->
                isConnecting = true
                infoMessage = "Signing in to Firebase..."
                roomRepository.signInAnonymously(
                    onSuccess = {
                        infoMessage = "Loading room ${code.trim().uppercase()}..."
                        roomRepository.loadRoomOnce(
                            roomCode = code,
                            onSuccess = { state ->
                                val engine = WindowGameEngine(state.players)
                                engine.restoreState(state)
                                gameEngine = engine
                                snapshot = engine.snapshot()
                                roomCode = code.trim().uppercase()
                                localPlayerName = localName
                                remoteVersion = state.version
                                isConnecting = false
                                infoMessage = "Joined room ${code.trim().uppercase()}. ${engine.currentPlayer()}'s turn"
                            },
                            onMissing = {
                                isConnecting = false
                                infoMessage = "Room not found."
                            },
                            onError = { error ->
                                isConnecting = false
                                infoMessage = error
                            },
                        )
                    },
                    onError = { error ->
                        isConnecting = false
                        infoMessage = error
                    },
                )
            },
            infoMessage = infoMessage,
            isConnecting = isConnecting,
        )
        return
    }

    val engine = gameEngine!!
    val snap = snapshot!!
    val isOnline = roomCode != null
    val isMyTurn = !isOnline || snap.currentPlayer == localPlayerName
    var screenScale by remember { mutableStateOf(1f) }
    var screenOffsetX by remember { mutableStateOf(0f) }
    var screenOffsetY by remember { mutableStateOf(0f) }
    val flingScope = rememberCoroutineScope()
    var flingJob by remember { mutableStateOf<Job?>(null) }

    fun startInertialPan(startX: Float, startY: Float) {
        if (abs(startX) + abs(startY) < 0.5f) return
        flingJob?.cancel()
        flingJob = flingScope.launch {
            var velocityX = startX
            var velocityY = startY
            while (screenScale > 1f && abs(velocityX) + abs(velocityY) > 0.5f) {
                screenOffsetX += velocityX
                screenOffsetY += velocityY
                velocityX *= 0.88f
                velocityY *= 0.88f
                delay(16)
            }
        }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = Color(0xFF0F381C),
    ) { padding ->
        Box(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitPointerEventScope {
                        var wasDragging = false
                        var lastPanX = 0f
                        var lastPanY = 0f
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val pressedPointers = event.changes.count { it.pressed }
                            if (pressedPointers >= 2) {
                                flingJob?.cancel()
                                val newScale = (screenScale * event.calculateZoom()).coerceIn(1f, 3f)
                                val pan = event.calculatePan()
                                screenScale = newScale
                                if (newScale <= 1.01f) {
                                    screenScale = 1f
                                    screenOffsetX = 0f
                                    screenOffsetY = 0f
                                } else {
                                    screenOffsetX += pan.x
                                    screenOffsetY += pan.y
                                }
                                wasDragging = false
                                event.changes.forEach { it.consume() }
                            } else if (pressedPointers == 1 && screenScale > 1f) {
                                val pan = event.calculatePan()
                                if (abs(pan.x) + abs(pan.y) > 1.5f) {
                                    flingJob?.cancel()
                                    screenOffsetX += pan.x
                                    screenOffsetY += pan.y
                                    lastPanX = pan.x
                                    lastPanY = pan.y
                                    wasDragging = true
                                    event.changes.forEach { it.consume() }
                                }
                            } else if (pressedPointers == 0 && wasDragging) {
                                startInertialPan(lastPanX, lastPanY)
                                wasDragging = false
                                lastPanX = 0f
                                lastPanY = 0f
                            }
                        }
                    }
                }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(12.dp)
                    .graphicsLayer {
                        scaleX = screenScale
                        scaleY = screenScale
                        translationX = screenOffsetX
                        translationY = screenOffsetY
                        transformOrigin = TransformOrigin(0.5f, 0.5f)
                    }
            ) {
                Text(
                    text = "Window Drinking Game",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = "Current Player: ${snap.currentPlayer}", fontWeight = FontWeight.SemiBold)
                if (roomCode != null) {
                    Text(text = "Room: $roomCode | You: ${localPlayerName ?: "spectator"}")
                }
                Text(text = "Deck: ${snap.deckSize} cards")
                Text(text = infoMessage)
                if (snap.mustSelectAdjacentToHandle) {
                    Text(
                        text = "Handle rule active: select a card adjacent to the handle.",
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))
                BoardView(
                    snapshot = snap,
                    cardLabel = { id -> engine.cardLabel(id) },
                    onCardClick = { position ->
                        if (!isMyTurn) {
                            infoMessage = "Waiting for ${snap.currentPlayer}."
                            return@BoardView
                        }
                        val options = engine.getValidOptionsForCard(position)
                        if (options.isEmpty()) {
                            infoMessage = "Invalid selection"
                            return@BoardView
                        }
                        if (options.size == 1) {
                            guessDialogTarget = position
                            guessDialogOption = options.first()
                        } else {
                            optionDialogTarget = position
                            optionDialogOptions = options
                        }
                    }
                )

                Spacer(modifier = Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = {
                            engine.endTurn()
                            refresh(pushOnlineState = true)
                            infoMessage = "${engine.currentPlayer()}'s turn"
                        },
                        enabled = isMyTurn && snap.turnCanEnd && snap.pendingRemovals.isEmpty(),
                    ) {
                        Text("End Turn")
                    }
                    Button(
                        onClick = { resetConfirmVisible = true }
                    ) {
                        Text("Reset Game")
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))
                StatsTable(snapshot = snap)
            }

            if (optionDialogTarget != null) {
                GuessOptionDialog(
                    options = optionDialogOptions,
                    onDismiss = {
                        optionDialogTarget = null
                        optionDialogOptions = emptyList()
                    },
                    onSelect = { option ->
                        guessDialogTarget = optionDialogTarget
                        guessDialogOption = option
                        optionDialogTarget = null
                        optionDialogOptions = emptyList()
                    }
                )
            }

            if (guessDialogTarget != null && guessDialogOption != null) {
                GuessDialog(
                    option = guessDialogOption!!,
                    onDismiss = {
                        guessDialogTarget = null
                        guessDialogOption = null
                    },
                    onGuess = { guess ->
                        val position = guessDialogTarget!!
                        val option = guessDialogOption!!
                        val result = engine.applyGuess(position, option, guess)
                        guessDialogTarget = null
                        guessDialogOption = null

                        if (result.invalidReason != null) {
                            infoMessage = result.invalidReason
                            refresh()
                            return@GuessDialog
                        }

                        if (result.requiresSameConfirmation) {
                            sameConfirmTarget = position
                            infoMessage = "Correct SAME guess. Confirm other players drank."
                        } else if (result.requiresRemovalConfirmation) {
                            removalConfirmVisible = true
                            infoMessage = "Wrong guess. Confirm removal of marked cards."
                        } else {
                            infoMessage = if (result.correct) "Correct guess." else "Wrong guess."
                        }

                        refresh(pushOnlineState = !result.requiresSameConfirmation)
                    }
                )
            }

            if (sameConfirmTarget != null) {
                MovableDialog {
                    Card {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Confirm Swallow")
                            Text("All players except ${snap.currentPlayer} must take one swallow.")
                            Button(onClick = {
                                engine.confirmSameGuess(sameConfirmTarget!!)
                                sameConfirmTarget = null
                                infoMessage = "Correct SAME guess confirmed."
                                refresh(pushOnlineState = true)
                            }) {
                                Text("Confirm")
                            }
                        }
                    }
                }
            }

            if (removalConfirmVisible) {
                MovableDialog {
                    Card {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Confirm Removal")
                            Text("Wrong guess: ${snap.currentPlayer} drinks ${engine.pendingPenalty}. Remove marked cards and redeal.")
                            Button(onClick = {
                                engine.confirmRemovals()
                                removalConfirmVisible = false
                                infoMessage = "Removal confirmed. ${engine.currentPlayer()} continues."
                                refresh(pushOnlineState = true)
                            }) {
                                Text("Confirm")
                            }
                        }
                    }
                }
            }

            if (resetConfirmVisible) {
                MovableDialog {
                    Card {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("Reset Game?", fontWeight = FontWeight.Bold)
                            Text("Start a new game and reset all stats?")
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = {
                                    engine.resetGame()
                                    resetConfirmVisible = false
                                    refresh(pushOnlineState = true)
                                    infoMessage = "New game started"
                                }) {
                                    Text("Reset")
                                }
                                TextButton(onClick = { resetConfirmVisible = false }) {
                                    Text("Cancel")
                                }
                            }
                        }
                    }
                }
            }

            if (endDialogVisible) {
                MovableDialog {
                    Card {
                        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Game Over", fontWeight = FontWeight.Bold)
                            Text("All cards are face-up.")
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = {
                                    engine.resetGame()
                                    endDialogVisible = false
                                    infoMessage = "New game started"
                                    refresh(pushOnlineState = true)
                                }) {
                                    Text("Play Again")
                                }
                                TextButton(onClick = { endDialogVisible = false }) {
                                    Text("Close")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MovableDialog(
    content: @Composable () -> Unit,
) {
    var offsetX by remember { mutableStateOf(0f) }
    var offsetY by remember { mutableStateOf(0f) }

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .offset { IntOffset(offsetX.roundToInt(), offsetY.roundToInt()) }
                .graphicsLayer {
                    scaleX = 0.75f
                    scaleY = 0.75f
                }
                .pointerInput(Unit) {
                    detectDragGestures { _, dragAmount ->
                        offsetX += dragAmount.x
                        offsetY += dragAmount.y
                    }
                }
        ) {
            content()
        }
    }
}

@Composable
private fun PlayerSetupScreen(
    onStartOffline: (List<String>) -> Unit,
    onCreateRoom: (List<String>, String) -> Unit,
    onJoinRoom: (String, String) -> Unit,
    infoMessage: String,
    isConnecting: Boolean,
) {
    var namesInput by remember { mutableStateOf("Alice, Bob, Charlie") }
    var localPlayerInput by remember { mutableStateOf("Alice") }
    var roomCodeInput by remember { mutableStateOf("") }

    fun parsedPlayers(): List<String> {
        return namesInput
            .split(",")
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .ifEmpty { listOf("Player1") }
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = Color(0xFF0F381C),
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Window Drinking Game", style = MaterialTheme.typography.headlineMedium)
            Spacer(modifier = Modifier.height(12.dp))
            Text(infoMessage)
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = namesInput,
                onValueChange = { namesInput = it },
                label = { Text("Player names (comma-separated)") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = localPlayerInput,
                onValueChange = { localPlayerInput = it },
                label = { Text("Your player name") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Button(onClick = {
                onStartOffline(parsedPlayers())
            }, enabled = !isConnecting) {
                Text("Start Offline Game")
            }
            Spacer(modifier = Modifier.height(8.dp))
            Button(
                onClick = {
                    val players = parsedPlayers()
                    val localName = localPlayerInput.trim().ifBlank { players.first() }
                    onCreateRoom(players, localName)
                },
                enabled = !isConnecting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isConnecting) "Connecting..." else "Create Online Room")
            }
            Spacer(modifier = Modifier.height(20.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = roomCodeInput,
                onValueChange = { roomCodeInput = it.uppercase() },
                label = { Text("Room code") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(8.dp))
            Button(
                onClick = {
                    val localName = localPlayerInput.trim().ifBlank { "Player1" }
                    onJoinRoom(roomCodeInput.trim(), localName)
                },
                enabled = roomCodeInput.isNotBlank() && !isConnecting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isConnecting) "Connecting..." else "Join Online Room")
            }
        }
    }
}

@Composable
private fun BoardView(
    snapshot: GameSnapshot,
    cardLabel: (Int) -> String,
    onCardClick: (Position) -> Unit,
) {
    val layout = listOf(
        listOf(true, true, true, true, true, false),
        listOf(true, false, true, false, true, false),
        listOf(true, true, true, true, true, true),
        listOf(true, false, true, false, true, false),
        listOf(true, true, true, true, true, false),
    )

    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val spacing = 6.dp
        val cardWidth = (maxWidth - spacing * 5) / 6
        val cardHeight = cardWidth * 1.38f

        Column(
            verticalArrangement = Arrangement.spacedBy(spacing),
            modifier = Modifier.fillMaxWidth()
        ) {
            for (r in layout.indices) {
                Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                    for (c in layout[r].indices) {
                        if (!layout[r][c]) {
                            Spacer(modifier = Modifier.size(width = cardWidth, height = cardHeight))
                            continue
                        }
                        val position = Position(r, c)
                        val cardId = snapshot.cardGrid[r][c]
                        val isFaceUp = snapshot.faceUp[r][c]
                        val isPendingRemoval = position in snapshot.pendingRemovals
                        val isSelectable = position in snapshot.validSelectable

                        val borderColor = when {
                            isPendingRemoval -> Color.Red
                            isSelectable && !isFaceUp -> Color.Gray
                            else -> Color.Transparent
                        }

                        Card(
                            modifier = Modifier
                                .size(width = cardWidth, height = cardHeight)
                                .border(2.dp, borderColor, RoundedCornerShape(8.dp))
                                .clickable(enabled = !isFaceUp && cardId != null) { onCardClick(position) },
                            shape = RoundedCornerShape(8.dp),
                        ) {
                            val imageRes = when {
                                cardId == null -> null
                                isFaceUp -> cardDrawableRes(cardId)
                                else -> R.drawable.card_back
                            }

                            if (imageRes != null) {
                                Image(
                                    painter = painterResource(id = imageRes),
                                    contentDescription = if (isFaceUp && cardId != null) cardLabel(cardId) else "Card",
                                    contentScale = ContentScale.Fit,
                                    modifier = Modifier
                                        .fillMaxSize(),
                                )
                            } else {
                                Box(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .background(Color(0xFF2E7D32)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text("?", color = Color.White)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun cardDrawableRes(cardId: Int): Int = when (cardId) {
    0 -> R.drawable.c1_v1
    1 -> R.drawable.c2_v1
    2 -> R.drawable.c3_v1
    3 -> R.drawable.c4_v1
    4 -> R.drawable.c1_v2
    5 -> R.drawable.c2_v2
    6 -> R.drawable.c3_v2
    7 -> R.drawable.c4_v2
    8 -> R.drawable.c1_v3
    9 -> R.drawable.c2_v3
    10 -> R.drawable.c3_v3
    11 -> R.drawable.c4_v3
    12 -> R.drawable.c1_v4
    13 -> R.drawable.c2_v4
    14 -> R.drawable.c3_v4
    15 -> R.drawable.c4_v4
    16 -> R.drawable.c1_v5
    17 -> R.drawable.c2_v5
    18 -> R.drawable.c3_v5
    19 -> R.drawable.c4_v5
    20 -> R.drawable.c1_v6
    21 -> R.drawable.c2_v6
    22 -> R.drawable.c3_v6
    23 -> R.drawable.c4_v6
    24 -> R.drawable.c1_v7
    25 -> R.drawable.c2_v7
    26 -> R.drawable.c3_v7
    27 -> R.drawable.c4_v7
    28 -> R.drawable.c1_v8
    29 -> R.drawable.c2_v8
    30 -> R.drawable.c3_v8
    31 -> R.drawable.c4_v8
    32 -> R.drawable.c1_v9
    33 -> R.drawable.c2_v9
    34 -> R.drawable.c3_v9
    35 -> R.drawable.c4_v9
    else -> R.drawable.card_back
}

@Composable
private fun GuessOptionDialog(
    options: List<GuessOption>,
    onDismiss: () -> Unit,
    onSelect: (GuessOption) -> Unit,
) {
    MovableDialog {
        Card {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Choose Guess Option", fontWeight = FontWeight.Bold)
                options.forEach { option ->
                    val label = if (option.type == "in-between") {
                        "In-between (${option.orientation.name.lowercase()})"
                    } else {
                        "Higher/Lower (${option.orientation.name.lowercase()})"
                    }
                    Button(onClick = { onSelect(option) }, modifier = Modifier.fillMaxWidth()) {
                        Text(label)
                    }
                }
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                    Text("Cancel")
                }
            }
        }
    }
}

@Composable
private fun GuessDialog(
    option: GuessOption,
    onDismiss: () -> Unit,
    onGuess: (GuessType) -> Unit,
) {
    MovableDialog {
        Card {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val title = if (option.type == "in-between") {
                    "Guess In-Between or Outside"
                } else {
                    "Guess Higher, Same, or Lower"
                }
                Text(title, fontWeight = FontWeight.Bold)
                option.guessOptions.forEach { guess ->
                    Button(onClick = { onGuess(guess) }, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            when (guess) {
                                GuessType.HIGHER -> "Higher"
                                GuessType.SAME -> "Same"
                                GuessType.LOWER -> "Lower"
                                GuessType.IN_BETWEEN -> "In-Between"
                                GuessType.OUTSIDE -> "Outside"
                            }
                        )
                    }
                }
                TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                    Text("Cancel")
                }
            }
        }
    }
}

@Composable
private fun StatsTable(snapshot: GameSnapshot) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(modifier = Modifier.fillMaxWidth().padding(12.dp)) {
            Text("Stats", fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(6.dp))

            snapshot.stats.forEach { (player, stats) ->
                Column(modifier = Modifier.fillMaxWidth()) {
                    Text(player, fontWeight = if (player == snapshot.currentPlayer) FontWeight.Bold else FontWeight.Medium)
                    Text("Drinks: ${stats.drinks} | Correct: ${stats.correct} | Wrong: ${stats.wrong}")
                    Text("Changed cards: ${stats.changedCards} | Turns: ${stats.turns}")
                    HorizontalDivider(modifier = Modifier.padding(vertical = 6.dp))
                }
            }
        }
    }
}
