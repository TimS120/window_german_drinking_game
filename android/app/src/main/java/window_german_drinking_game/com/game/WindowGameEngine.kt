package window_german_drinking_game.com.game

import kotlin.random.Random

data class Position(val row: Int, val col: Int)

enum class GuessType {
    HIGHER, SAME, LOWER, IN_BETWEEN, OUTSIDE
}

enum class Orientation {
    HORIZONTAL, VERTICAL
}

data class GuessOption(
    val type: String,
    val guessOptions: List<GuessType>,
    val neighbors: List<Position>,
    val orientation: Orientation,
)

data class PlayerStats(
    val drinks: Int,
    val correct: Int,
    val wrong: Int,
    val changedCards: Int,
    val turns: Int,
)

data class GameSnapshot(
    val cardGrid: List<List<Int?>>,
    val faceUp: List<List<Boolean>>,
    val currentPlayer: String,
    val deckSize: Int,
    val mustSelectAdjacentToHandle: Boolean,
    val turnCanEnd: Boolean,
    val validSelectable: Set<Position>,
    val stats: Map<String, PlayerStats>,
    val pendingRemovals: Set<Position>,
    val gameEnded: Boolean,
)

class WindowGameEngine(playersInput: List<String>) {
    private val ranks = listOf("6", "7", "8", "9", "10", "U", "O", "K", "A")
    private val suits = listOf("E", "B", "H", "S")

    private val layout = listOf(
        listOf(true, true, true, true, true, false),
        listOf(true, false, true, false, true, false),
        listOf(true, true, true, true, true, true),
        listOf(true, false, true, false, true, false),
        listOf(true, true, true, true, true, false),
    )

    private val corners = setOf(
        Position(0, 0), Position(0, 4), Position(4, 0), Position(4, 4)
    )
    private val handle = Position(2, 5)

    val players = playersInput.ifEmpty { listOf("Player1") }

    private var currentPlayerIdx = 0
    private var turnStartFaceUp = 0

    private val drinkCount = mutableMapOf<String, Int>()
    private val correctGuessCount = mutableMapOf<String, Int>()
    private val wrongGuessCount = mutableMapOf<String, Int>()
    private val changedCards = mutableMapOf<String, Int>()
    private val turns = mutableMapOf<String, Int>()

    private var deck = mutableListOf<Int>()
    private var cardGrid = MutableList(layout.size) { MutableList<Int?>(layout[0].size) { null } }
    private var faceUp = MutableList(layout.size) { MutableList(layout[0].size) { false } }

    var pendingRemovals: Set<Position> = emptySet()
        private set
    var pendingPenalty = 0
        private set
    var mustSelectAdjacentToHandle = true
        private set
    var turnCanEnd = false
        private set

    init {
        initStats()
        resetGame()
    }

    fun resetGame() {
        deck = (0 until ranks.size * suits.size).toMutableList()
        deck.shuffle(Random.Default)
        cardGrid = MutableList(layout.size) { MutableList<Int?>(layout[0].size) { null } }
        faceUp = MutableList(layout.size) { MutableList(layout[0].size) { false } }

        for (r in layout.indices) {
            for (c in layout[r].indices) {
                if (!layout[r][c]) continue
                val card = if (deck.isNotEmpty()) deck.removeLast() else null
                cardGrid[r][c] = card
                faceUp[r][c] = card != null && (Position(r, c) in corners || Position(r, c) == handle)
            }
        }

        pendingRemovals = emptySet()
        pendingPenalty = 0
        mustSelectAdjacentToHandle = true
        turnCanEnd = false
        turnStartFaceUp = countFaceUpCards()
        incrementTurn(currentPlayer())
    }

    private fun initStats() {
        players.forEach { player ->
            drinkCount[player] = 0
            correctGuessCount[player] = 0
            wrongGuessCount[player] = 0
            changedCards[player] = 0
            turns[player] = 0
        }
    }

    fun currentPlayer(): String = players[currentPlayerIdx]

    fun endTurn() {
        if (!turnCanEnd) return
        val player = currentPlayer()
        val delta = countFaceUpCards() - turnStartFaceUp
        changedCards[player] = (changedCards[player] ?: 0) + delta

        currentPlayerIdx = (currentPlayerIdx + 1) % players.size
        turnStartFaceUp = countFaceUpCards()
        incrementTurn(currentPlayer())
        turnCanEnd = false
    }

    fun cardLabel(cardId: Int): String {
        val rank = ranks[cardId / 4]
        val suit = suits[cardId % 4]
        return "$rank.$suit"
    }

    fun isValidSlot(position: Position): Boolean {
        return position.row in layout.indices && position.col in layout[position.row].indices && layout[position.row][position.col]
    }

    fun isFaceUp(position: Position): Boolean = faceUp[position.row][position.col]

    fun cardAt(position: Position): Int? = cardGrid[position.row][position.col]

    fun getValidOptionsForCard(position: Position): List<GuessOption> {
        val r = position.row
        val c = position.col
        if (!isValidSlot(position) || faceUp[r][c]) return emptyList()
        if (mustSelectAdjacentToHandle && position !in adjacentPositions(handle)) return emptyList()

        val neighbors = mutableListOf<Pair<Position, String>>()
        for (neighbor in adjacentPositions(position)) {
            if (isFaceUp(neighbor)) {
                val direction = when {
                    neighbor.row == r - 1 && neighbor.col == c -> "north"
                    neighbor.row == r + 1 && neighbor.col == c -> "south"
                    neighbor.row == r && neighbor.col == c - 1 -> "west"
                    neighbor.row == r && neighbor.col == c + 1 -> "east"
                    else -> ""
                }
                neighbors.add(neighbor to direction)
            }
        }

        val horizontal = neighbors.filter { it.second == "east" || it.second == "west" }.map { it.first }
        val vertical = neighbors.filter { it.second == "north" || it.second == "south" }.map { it.first }

        val options = mutableListOf<GuessOption>()

        if (horizontal.size >= 2) {
            val left = horizontal.minBy { it.col }
            val right = horizontal.maxBy { it.col }
            options.add(
                GuessOption(
                    type = "in-between",
                    guessOptions = listOf(GuessType.IN_BETWEEN, GuessType.OUTSIDE),
                    neighbors = listOf(left, right),
                    orientation = Orientation.HORIZONTAL,
                )
            )
        } else if (horizontal.size == 1) {
            options.add(
                GuessOption(
                    type = "higher-lower",
                    guessOptions = listOf(GuessType.HIGHER, GuessType.SAME, GuessType.LOWER),
                    neighbors = listOf(horizontal.first()),
                    orientation = Orientation.HORIZONTAL,
                )
            )
        }

        if (vertical.size >= 2) {
            val top = vertical.minBy { it.row }
            val bottom = vertical.maxBy { it.row }
            options.add(
                GuessOption(
                    type = "in-between",
                    guessOptions = listOf(GuessType.IN_BETWEEN, GuessType.OUTSIDE),
                    neighbors = listOf(top, bottom),
                    orientation = Orientation.VERTICAL,
                )
            )
        } else if (vertical.size == 1) {
            options.add(
                GuessOption(
                    type = "higher-lower",
                    guessOptions = listOf(GuessType.HIGHER, GuessType.SAME, GuessType.LOWER),
                    neighbors = listOf(vertical.first()),
                    orientation = Orientation.VERTICAL,
                )
            )
        }

        val inBetweenOptions = options.filter { it.type == "in-between" }
        return if (inBetweenOptions.isNotEmpty()) inBetweenOptions else options
    }

    fun validSelectablePositions(): Set<Position> {
        val valid = mutableSetOf<Position>()
        for (r in layout.indices) {
            for (c in layout[r].indices) {
                val position = Position(r, c)
                if (!layout[r][c] || faceUp[r][c]) continue
                if (getValidOptionsForCard(position).isNotEmpty()) {
                    valid.add(position)
                }
            }
        }
        return valid
    }

    fun applyGuess(position: Position, option: GuessOption, guess: GuessType): GuessResult {
        val r = position.row
        val c = position.col
        if (!isValidSlot(position) || faceUp[r][c]) {
            return GuessResult(invalidReason = "Invalid card selection")
        }
        if (guess !in option.guessOptions) {
            return GuessResult(invalidReason = "Invalid guess for this option")
        }

        when (option.type) {
            "higher-lower" -> {
                val neighbor = option.neighbors.first()
                val result = resolveHigherSameLower(position, neighbor, guess)
                return if (result.requiresSameConfirmation) result else finalizeGuess(position, result.correct)
            }
            "in-between" -> {
                val n1 = option.neighbors[0]
                val n2 = option.neighbors[1]
                val inRange = isBetween(cardAt(position)!!, cardAt(n1)!!, cardAt(n2)!!)
                val correct = (guess == GuessType.IN_BETWEEN && inRange) || (guess == GuessType.OUTSIDE && !inRange)
                return finalizeGuess(position, correct)
            }
            else -> return GuessResult(invalidReason = "Unknown option")
        }
    }

    fun confirmSameGuess(position: Position) {
        val current = currentPlayer()
        players.filter { it != current }.forEach { player ->
            drinkCount[player] = (drinkCount[player] ?: 0) + 1
        }
        finalizeGuess(position, true)
    }

    fun confirmRemovals() {
        pendingRemovals.forEach { pos ->
            val card = cardGrid[pos.row][pos.col]
            if (card != null) {
                deck.add(card)
            }
            cardGrid[pos.row][pos.col] = null
            faceUp[pos.row][pos.col] = false
        }

        mustSelectAdjacentToHandle = handle in pendingRemovals
        pendingRemovals = emptySet()
        pendingPenalty = 0

        deck.shuffle(Random.Default)
        redealSpots()
    }

    fun snapshot(): GameSnapshot {
        val stats = players.associateWith { player ->
            PlayerStats(
                drinks = drinkCount[player] ?: 0,
                correct = correctGuessCount[player] ?: 0,
                wrong = wrongGuessCount[player] ?: 0,
                changedCards = changedCards[player] ?: 0,
                turns = turns[player] ?: 0,
            )
        }
        return GameSnapshot(
            cardGrid = cardGrid.map { it.toList() },
            faceUp = faceUp.map { it.toList() },
            currentPlayer = currentPlayer(),
            deckSize = deck.size,
            mustSelectAdjacentToHandle = mustSelectAdjacentToHandle,
            turnCanEnd = turnCanEnd,
            validSelectable = validSelectablePositions(),
            stats = stats,
            pendingRemovals = pendingRemovals,
            gameEnded = checkGameEnd(),
        )
    }

    private fun resolveHigherSameLower(position: Position, neighbor: Position, guess: GuessType): GuessResult {
        val cardRank = rankIndex(cardAt(position)!!)
        val neighborRank = rankIndex(cardAt(neighbor)!!)
        val correct = when (guess) {
            GuessType.HIGHER -> cardRank > neighborRank
            GuessType.LOWER -> cardRank < neighborRank
            GuessType.SAME -> cardRank == neighborRank
            else -> false
        }
        if (!correct) return GuessResult(correct = false)

        return if (guess == GuessType.SAME) {
            GuessResult(correct = true, requiresSameConfirmation = true)
        } else {
            GuessResult(correct = true)
        }
    }

    private fun finalizeGuess(position: Position, isCorrect: Boolean): GuessResult {
        val current = currentPlayer()
        if (isCorrect) {
            faceUp[position.row][position.col] = true
            correctGuessCount[current] = (correctGuessCount[current] ?: 0) + 1
            mustSelectAdjacentToHandle = false
            turnCanEnd = true
            pendingRemovals = emptySet()
            pendingPenalty = 0
            return GuessResult(correct = true, gameEnded = checkGameEnd())
        }

        val connected = collectConnectedOpenCards(position)
        val totalRemoved = connected.toMutableSet().apply { add(position) }
        val penalty = totalRemoved.size

        pendingRemovals = totalRemoved
        pendingPenalty = penalty
        wrongGuessCount[current] = (wrongGuessCount[current] ?: 0) + 1
        drinkCount[current] = (drinkCount[current] ?: 0) + penalty
        turnCanEnd = false

        return GuessResult(correct = false, requiresRemovalConfirmation = true)
    }

    private fun collectConnectedOpenCards(start: Position): Set<Position> {
        val visited = mutableSetOf<Position>()
        val stack = ArrayDeque<Position>()
        stack.add(start)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            if (!visited.add(current)) continue
            for (neighbor in adjacentPositions(current)) {
                if (isFaceUp(neighbor) && neighbor !in visited) {
                    stack.add(neighbor)
                }
            }
        }
        return visited
    }

    private fun redealSpots() {
        for (r in layout.indices) {
            for (c in layout[r].indices) {
                if (!layout[r][c]) continue
                if (cardGrid[r][c] == null && deck.isNotEmpty()) {
                    cardGrid[r][c] = deck.removeLast()
                    faceUp[r][c] = Position(r, c) in corners || Position(r, c) == handle
                }
            }
        }
    }

    private fun countFaceUpCards(): Int {
        var count = 0
        for (r in layout.indices) {
            for (c in layout[r].indices) {
                if (layout[r][c] && faceUp[r][c]) count++
            }
        }
        return count
    }

    private fun checkGameEnd(): Boolean {
        for (r in layout.indices) {
            for (c in layout[r].indices) {
                if (layout[r][c] && !faceUp[r][c]) return false
            }
        }
        return true
    }

    private fun adjacentPositions(position: Position): List<Position> {
        val candidates = listOf(
            Position(position.row - 1, position.col),
            Position(position.row + 1, position.col),
            Position(position.row, position.col - 1),
            Position(position.row, position.col + 1),
        )
        return candidates.filter { isValidSlot(it) }
    }

    private fun rankIndex(cardId: Int): Int = cardId / 4

    private fun isBetween(cardId: Int, boundary1: Int, boundary2: Int): Boolean {
        val r1 = rankIndex(boundary1)
        val r2 = rankIndex(boundary2)
        val low = minOf(r1, r2)
        val high = maxOf(r1, r2)
        val rank = rankIndex(cardId)
        return rank in low..high
    }

    private fun incrementTurn(player: String) {
        turns[player] = (turns[player] ?: 0) + 1
    }
}

data class GuessResult(
    val correct: Boolean = false,
    val invalidReason: String? = null,
    val requiresSameConfirmation: Boolean = false,
    val requiresRemovalConfirmation: Boolean = false,
    val gameEnded: Boolean = false,
)
