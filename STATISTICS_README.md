# Statistics move adviser

Select **Propose best move → Pure statistics**. The adviser estimates the
current player's remaining drinks through game completion. It does not execute
moves or learn from opponents. The same adviser is the ONNX failure fallback.

## Information boundary and beliefs

`WindowGameEngine.publicObservation()` copies face-up cards, turn flags, player
information, and the last 16 public events. Face-down identities are null and
no deck cards are copied. It supplies both the synchronous API and the
asynchronous UI API; actual hidden cards and RNG state never enter the search.

The adviser reconstructs 128 sampled possible arrangements from the oldest
visible board in that window. Each public reveal conditions and resamples those
arrangements. A successful reveal is present in the next event's board or the
current board; wrong guesses include the publicly revealed removal cards.

Hidden cards are grouped by which deal/shuffle they came from. Reveals condition
only the appropriate group. After a failure, removed cards join the sampled
deck and only replacement slots receive the new shuffled group. Untouched
face-down slots retain their earlier group. This allows publicly returned aces,
for example, to favor replacements over untouched cards. Suits identify physical
copies, although only ranks determine successful guesses.

These are approximate probabilities, not known hidden identities. If the finite
sample cannot support a historical observation, the adviser rebuilds from the
current public board and includes “current board only” in its explanation.
Nothing is retained between requests or saved across sessions. Older events
are not incorporated into accumulated beliefs.

## Future search

All legal actions receive success estimates and expected immediate penalties,
including the complete connected removal group. When all remaining hidden cards are exchangeable,
success percentages come from exact remaining rank counts. Otherwise they
come from sampled beliefs. Sample unanimity is not treated as mathematical
certainty unless the broader public rank support also proves the guess certain.

Up to nine distinct candidates enter future search: four with the lowest
immediate expected penalties, four with the highest success estimates, and
passing whenever legal. Each candidate is evaluated on paired sampled worlds
and shuffle seeds so comparisons have less noise. The sampled first-move
penalty is replaced with its probability-weighted expectation, further reducing
noise when only a few scenarios fit the budget.

The fixed opponent mixture has three equally represented styles:

- Casual: sometimes chooses a random legal guess; passes with probability 45%.
- Probability-aware: favors success probability; passes with probability 70%.
- Cautious: favors low expected immediate penalties; passes with probability 95%.

All styles take publicly certain guesses before considering passing. The
advised player's rollout continuation favors low expected penalties and passes
when available unless a guess is certain. Continuation policies use only their
simulated public boards, never the sampled hidden answers, and do not adapt to
human behavior. They are inexpensive approximations; they do not recursively
run the whole adviser at every simulated decision.

The rules engine resolves sampled outcomes, removals, shuffles, passing, and
“same” penalties charged by other players. The objective counts only the
advised player's drinks. Each rollout stops after completion or 48 actions.
For unfinished games, an explicit tail approximation uses remaining hidden
slots, the safest current failure/success odds, and equal exposure across seats.
The returned estimate therefore covers future drinks approximately, rather
than counting only the next move or treating truncation as a free completion.

## Runtime and presentation

The default search targets 180 ms, with 3–12 complete paired scenario rounds.
Rounds finish in groups of three so each opponent style has equal weight.
Belief reconstruction and the minimum three rounds are mandatory; completing
a group can overshoot the time target. Fixed bounds on particles, candidates,
rounds, and rollout length limit total work even on slower hardware.

Installed Flutter apps run the search through `compute()` in a worker isolate.
Flutter web runs `compute()` on its main event loop, so its fixed work bounds
still matter. No smartphone latency guarantee is inferred from desktop timing.

Suggestions show estimated next-guess success, estimated remaining personal
drinks, and a short English reason. Passing displays “no immediate drinks”
instead of an artificial 100% card-success percentage. Reasons such as “Lower
expected future drinks” describe the criterion used; they are not proofs of
optimality. Neither the percentages nor the future estimates are calibrated
confidence intervals.

## Validation and limitations

Run `flutter test` and `flutter analyze` from `app/`. Tests cover hidden-card
permutation invariance, replacement versus untouched-card beliefs, the 16-event
boundary, legal and non-mutating suggestions, a guaranteed finishing move,
pending confirmations, and the asynchronous result path.

The method is bounded approximate search, not an exhaustive optimal solver.
Shortlisting, particle depletion, fixed opponent assumptions, simple continuation
policies, and the tail approximation can affect recommendations. Superiority
over a trained RL policy requires a separate controlled gameplay comparison;
it is not claimed by this implementation.
