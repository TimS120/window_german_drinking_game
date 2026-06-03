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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
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
    var gameEngine by remember { mutableStateOf<WindowGameEngine?>(null) }
    var snapshot by remember { mutableStateOf<GameSnapshot?>(null) }
    var infoMessage by remember { mutableStateOf("Enter player names to start") }

    var optionDialogTarget by remember { mutableStateOf<Position?>(null) }
    var optionDialogOptions by remember { mutableStateOf<List<GuessOption>>(emptyList()) }

    var guessDialogTarget by remember { mutableStateOf<Position?>(null) }
    var guessDialogOption by remember { mutableStateOf<GuessOption?>(null) }

    var sameConfirmTarget by remember { mutableStateOf<Position?>(null) }
    var removalConfirmVisible by remember { mutableStateOf(false) }
    var resetConfirmVisible by remember { mutableStateOf(false) }
    var endDialogVisible by remember { mutableStateOf(false) }

    fun refresh() {
        snapshot = gameEngine?.snapshot()
        if (snapshot?.gameEnded == true) {
            endDialogVisible = true
        }
    }

    if (gameEngine == null || snapshot == null) {
        PlayerSetupScreen(
            onStart = { players ->
                gameEngine = WindowGameEngine(players)
                snapshot = gameEngine!!.snapshot()
                infoMessage = "${snapshot!!.currentPlayer}'s turn"
            }
        )
        return
    }

    val engine = gameEngine!!
    val snap = snapshot!!
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

    Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
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
                            refresh()
                            infoMessage = "${engine.currentPlayer()}'s turn"
                        },
                        enabled = snap.turnCanEnd && snap.pendingRemovals.isEmpty(),
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

                        refresh()
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
                                refresh()
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
                                refresh()
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
                                    refresh()
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
                                    refresh()
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
private fun PlayerSetupScreen(onStart: (List<String>) -> Unit) {
    var namesInput by remember { mutableStateOf("Alice, Bob, Charlie") }

    Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Window Drinking Game", style = MaterialTheme.typography.headlineMedium)
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = namesInput,
                onValueChange = { namesInput = it },
                label = { Text("Player names (comma-separated)") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(12.dp))
            Button(onClick = {
                val players = namesInput
                    .split(",")
                    .map { it.trim() }
                    .filter { it.isNotBlank() }
                onStart(players)
            }) {
                Text("Start Game")
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
                                        .fillMaxSize()
                                        .graphicsLayer { rotationZ = 90f },
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

private fun cardDrawableRes(cardId: Int): Int {
    val rankNames = listOf("sechs", "sieben", "acht", "neun", "zehn", "unter", "ober", "koenig", "ass")
    val suitNames = listOf("eichel", "blatt", "herz", "schelln")
    val rank = rankNames[cardId / 4]
    val suit = suitNames[cardId % 4]
    val key = "${suit}_${rank}"
    return when (key) {
        "blatt_acht" -> R.drawable.blatt_acht
        "blatt_ass" -> R.drawable.blatt_ass
        "blatt_koenig" -> R.drawable.blatt_koenig
        "blatt_neun" -> R.drawable.blatt_neun
        "blatt_ober" -> R.drawable.blatt_ober
        "blatt_sechs" -> R.drawable.blatt_sechs
        "blatt_sieben" -> R.drawable.blatt_sieben
        "blatt_unter" -> R.drawable.blatt_unter
        "blatt_zehn" -> R.drawable.blatt_zehn
        "eichel_acht" -> R.drawable.eichel_acht
        "eichel_ass" -> R.drawable.eichel_ass
        "eichel_koenig" -> R.drawable.eichel_koenig
        "eichel_neun" -> R.drawable.eichel_neun
        "eichel_ober" -> R.drawable.eichel_ober
        "eichel_sechs" -> R.drawable.eichel_sechs
        "eichel_sieben" -> R.drawable.eichel_sieben
        "eichel_unter" -> R.drawable.eichel_unter
        "eichel_zehn" -> R.drawable.eichel_zehn
        "herz_acht" -> R.drawable.herz_acht
        "herz_ass" -> R.drawable.herz_ass
        "herz_koenig" -> R.drawable.herz_koenig
        "herz_neun" -> R.drawable.herz_neun
        "herz_ober" -> R.drawable.herz_ober
        "herz_sechs" -> R.drawable.herz_sechs
        "herz_sieben" -> R.drawable.herz_sieben
        "herz_unter" -> R.drawable.herz_unter
        "herz_zehn" -> R.drawable.herz_zehn
        "schelln_acht" -> R.drawable.schelln_acht
        "schelln_ass" -> R.drawable.schelln_ass
        "schelln_koenig" -> R.drawable.schelln_koenig
        "schelln_neun" -> R.drawable.schelln_neun
        "schelln_ober" -> R.drawable.schelln_ober
        "schelln_sechs" -> R.drawable.schelln_sechs
        "schelln_sieben" -> R.drawable.schelln_sieben
        "schelln_unter" -> R.drawable.schelln_unter
        "schelln_zehn" -> R.drawable.schelln_zehn
        else -> R.drawable.card_back
    }
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
