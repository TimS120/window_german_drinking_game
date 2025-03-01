# Window - a German drinking game

This project's purpose is the:
- Development of the basic functionality of the game
- Creation of a simulated dataset
- The creation and training of an AI-model for the prediction of the next best move


## Game Explanation

### Setup
- The used cards are a German Deck (Order: 6 < 7 < 8 < 9 < 10 < U < O < K < A) with its four types of cards (Eichel, Blatt, Herz, Schelle)
- Arrange the cards in a “window” formation: all **corner** cards and the **handle** card are face-up; all others face-down.  
- The remaining cards form a face-down stack.  
- Typically, 3–8 players participate (but any number from 1 to 100 is also possible).

### Gameplay
1. **Initial Guess**:  
   - The first player must guess the face-down card **adjacent** to the handle (higher or lower than the handle’s rank).  
2. **In-Between Guesses**:  
   - If a face-down card is **between two face-up cards**, the guess is whether its rank is *in between* or *outside* those two ranks (ties with boundary ranks count as *in between*).  
3. **Multiple Boundaries**:  
   - If a face-down card touches more than one pair of face-up cards (e.g., horizontally and vertically), the player must choose **either** the horizontal **or** the vertical pair as the boundaries.  
   - “Around the corner” (mixing a horizontal card with a vertical card) is not allowed.  
4. **Correct Guess**:  
   - The card is turned face-up.  
   - The player may continue guessing another card or pass the turn.  
5. **Wrong Guess**:  
   - The player drinks a number of times equal to the **number of adjacent face-up cards** around the guessed card.  
   - Those face-up cards, plus the incorrectly guessed card, are removed from the layout and shuffled back into the deck.  
   - Missing spots are redealt: **corners and handle** are always redealt face-up, others face-down.  
   - The **same player** takes the next turn (if the handle is removed, it is replaced face-up, and the same player restarts by guessing the new handle-adjacent card).

### Winning Condition
- The game ends when **all cards** in the window are face-up.

### Additional Notes
- Only **ranks** matter (6–10, U, O, K, A); suits/colors are irrelevant.  
- “In between” includes matching the boundary ranks.
