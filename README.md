![Window game](./resources/docs/full_game.png)

# Window - a German drinking game

This project's purpose is the:
- Development of the basic functionality of the German "Window" drinking game
- The creation and training of a DRL-Agend for the prediction of the next best move


## Table of Contents
- [Game Explanation](#game-explanation)
   - [Gameplay](#gameplay)
   - [Winning Condition](#winning-condition)
   - [Additional Notes](#additional-notes)
- [Development Documentation](#development-documentation)
   - [Architecture](#architecture)
   - [Agent/ Training](#agent-training)


## Game Explanation

### Setup
- The cards used are from a German deck (order: 6 < 7 < 8 < 9 < 10 < U < O < K < A) with four suits (Eichel, Blatt, Herz, Schelle)
- Arrange the cards in a “window” formation: all **corner** cards and the **handle** card are face-up; all others face-down.  
- The remaining cards form a face-down stack.  
- Typically, 3–8 players participate (but any number from 1 to 100 is also possible).

### Gameplay
1. **Initial/ Handle Rule**:
   - At the start of the game and whenever the handle is removed, the only valid move is to select the card adjacent to the handle. The player must guess if that face‑down card is higher, same, or lower than the handle’s rank.
2. **Guesses**:
   - If a face-down card is next to **one** (horizontally or vertically) face-up card, then the guess is either *higher*, *same* or *lower*
   - If a face-down card is **between two face-up cards**, the guess is whether its rank is *in between* or *outside* those two ranks (ties with boundary ranks count as *in between*).  
3. **Multiple Boundaries**:
   - If a face-down card touches more than one pair of face-up cards (e.g., horizontally and vertically), the player must choose **either** the horizontal **or** the vertical pair as the boundaries.  
   - “Around the corner” (mixing a horizontal card with a vertical card) is not allowed.  
4. **Correct Guess**:
   - The card is turned face-up.  
   - Special rule for 'same' guesses: If a player correctly guesses 'same', all other players must take one swallow.
   - The player may continue guessing another card or pass the turn.  
5. **Wrong Guess**:
   - The player drinks a number of times equal to the total number of cards removed.
   - The guessed card is removed along with every open card that is directly or indirectly adjoining it (i.e. if an open card touches an open card that is adjacent to the guessed card, it is also removed).
   - If the handle (the card at the handle position) is removed in this process, it is immediately redealt face-up and the next turn must be played on a card adjacent to the new handle.
   - All removed cards are shuffled back into the deck.
   - Missing spots are redealt: corners and handle are always redealt face-up, others face-down.
   - The same player takes the next turn.

### Winning Condition
- The game ends when **all cards** in the window are face-up.

### Additional Notes
- Only **ranks** matter (6–10, U, O, K, A); suits/colors are irrelevant.  
- “In between” includes matching the boundary ranks.
- If a face‑down card touches face‑up cards in more than one configuration (for example, one horizontal neighbor and two vertical neighbors), then if an in‑between option is available (i.e. from a pair of vertical or horizontal neighbors), it must be used. The player is not allowed to choose a higher/same/lower guess in such cases; they must make the in‑between/outside guess based on the available pair.
- “Around the corner” (mixing a horizontal card with a vertical card) is not allowed.

---
# Development Documentation

## Architecture
- simulation_env.py: Entry point for the whole game via playing player vs. player or player vs. bot
- main.py: Deprecated version of the game (player vs. player)
<br />
<br />
- agent.py: The agent that uses a trained model to act as the bot opponent
- config.py: Definitions and configuration parameters for the game
- game.py: The core game
- model.py: The model of the agent
- train.py: The trainings script for the model
- utils.py: Helper functions for the whole game


## Agent/ Training
1. By not sorting out all invalid actions, the model will do too many invalid actions and learning will be (too) slow:
<div align="center">
    <img src="resources/docs/development/runs1.png" width="50%" style="display:inline-block;">
</div>
<br />

2. For that nearly all invalid moves are multiplied by 0.0, so that the move will not be selected by the model. That increases the performance of the model. A test is made with a few episodes: 
<div align="center">
    <img src="resources/docs/development/runs2.png" width="50%" style="display:inline-block;">
</div>
<br />

3. The next development steps could include using previous board states as input (for this purpose the lstm-architecture was selected).

4. A further refinement of the reward function should also be considered.
