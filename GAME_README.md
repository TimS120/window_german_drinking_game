# Window game rules

## Goal

Turn every card in the window face-up while taking as few drinks as possible.
Only ranks matter; the German-deck order is:

`6 < 7 < 8 < 9 < 10 < U < O < K < A`

Suits (Eichel, Blatt, Herz, Schelle) do not affect a guess.

## Setup

- Use a 36-card German deck: nine ranks in four suits.
- Deal cards into the window-shaped layout.
- The four corners and the handle are face-up; all other window cards are
  face-down. The remaining cards form the deck.
- Enter one or more players. The app selects the first player.

## Making a guess

Select a face-down card adjacent to a face-up card. The available guess is
determined by the face-up neighbours in the same row or column.

### Handle rule

At the start and after a redeal that removed the handle, the next card must be
adjacent to the handle. Guess **higher**, **same**, or **lower** than it.

### One visible neighbour

With one relevant face-up neighbour, guess **higher**, **same**, or **lower**.

### Two visible neighbours on one line

With two face-up boundary cards in a row or column, guess **in between** or
**outside** their ranks. A rank equal to either boundary counts as in between.
Horizontal and vertical neighbours may not be mixed (“around the corner”).

### Multiple possible lines

If both orientations are possible, choose one. If either orientation has two
face-up boundaries, an in-between/outside guess is mandatory; higher/same/lower
cannot be used instead.

## Result of a guess

### Correct

- The selected card turns face-up.
- A correctly guessed **same** rank makes every other player take one drink;
  the app requests confirmation.
- The current player may guess again or pass.
- The game ends immediately when all window cards are face-up.

### Wrong

- The current player takes one drink for every card removed.
- The selected card and every directly or indirectly connected face-up card
  are removed. This can be a whole connected group, not only immediate
  neighbours.
- Removed cards return to the deck and are shuffled.
- Empty places are redealt. Corners and the handle are always face-up after a
  redeal; all other replacements are face-down.
- If the handle was removed, its replacement is face-up and the handle rule
  applies again.
- A wrong guess does not pass the turn: the same player continues.

## Passing and winning

A player may pass only after at least one correct guess in their turn. Passing
moves play to the next player. The game finishes when every window position is
face-up. Online rooms use these same rules; the host validates every move.
