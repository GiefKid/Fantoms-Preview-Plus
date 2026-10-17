# Fantom's Preview Plus

A QoL mod for Balatro that previews your score before you submit a hand. Originally "Fantom's Preview" 
by Fantom and Divvy, forked, updated, and in-game tests by GiefKid.

## Installation

1. If you have the original **Fantom's Preview** installed, either disable or remove it from (`%appdata%\Balatro\Mods`). They conflict since they all patch the same vanilla files.
2. Install [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector?tab=readme-ov-file#manual-installation) (required, this mod is a set of Lovely patches).
3. Download the [latest release](https://github.com/GiefKid/Fantoms-Preview-Plus/releases/latest) and extract it into its own folder inside your Balatro `Mods` folder (`%appdata%\Balatro\Mods`), so you end up with `Mods\Fantoms-Preview-Plus\lovely.toml` etc.
4. Launch the game. The score preview appears in the left UI when turned on.

## What's changed

1. **Instant Calculation**: The old button had scoring calculated with an artificial 5-second delay before showing a score.
   I couldn't find any actual need for the delay, so it now calculates instantly, and I replaced the button with an on/off visibility toggle.
2. **Probability and Range Animations**: When the range comes from luck (Misprint, Lucky Cards, etc), the low number
   cycles through every score you could get, and a "(NN%)" shows your chance to beat the blind if not at 0% or 100%.
   Also works with "The Hook", since every pair of cards it can discard is equally likely.
   If probability is complicated by too many different sources, no % or animation appears, but the worst/best case scenario still shows.
   Both adjustable in settings in settings gear button or the Mods menu. 
3. **Face-down held-card leak fixed.** In the original Fantom's Preview, if the player owns a Steel Card or certain jokers,
   face down cards could be deduced by the player due to the simulation accounting for their value.  Now, the simulation uses
   bounded score ranges, showing the worst vs best-case scenarios but not revealing if the face down card affects the score.
4. **Blind-relative pace coloring**: In addition to the original gold/white coloring, a new red behind-pace color
   shows if handScored < (requiredScore / handsRemaining). Orange shows if owning Mr. Bones and over 25%.
5. **Fixed numerous scoring and performance issues with "The Hook" boss blind**, including random event queue
   hangs when using Plasma Deck, instead just calculating all combinations.
6. **Hover tooltips**: Tooltips explaining why a score has a range or looks abnormal can be accessed by hovering over the score.
7. **Number formatting**: Ranges get compact M/B notation for million/billion to prevent left UI elements from expanding if
   numbers grew too large.
8. **Predictor Visibility**: The predictor is only visible when at least one card is selected or a hand is being scored, and
   should be invisible otherwise.
9. **Various correctness fixes**: See [v1.0.0-release-notes.md](v1.0.0-release-notes.md) for the full changelist between this version and original Fantom's Preview.
10. **Unknown Mod Detection**: A "?" is appended to the score if an unprogrammed modded joker is detected.

## Related
A new mod in its final stages of development, "Score Simulator", will heavily use this edition of Fantom's Preview. It will allow you to simulate hundreds of
hands, joker purchases, and other scoring elements without actually going into battle, removing the guesswork of what buying/selling specific jokers
will do to your run. That mod will be linked here. Release date is planned before end of 2026.

## Future Plans
- Score Simulator
- Better Modded Joker/Mechanic Support (mainly tested on Vanilla Balatro)
- Improve Probability/Animation to handle multiple probability sources (for example, lucky + heart with bloodstone)
- Adjust to Balatro v1.1, whenever that releases
- Get in contact eventually with original creators?
     
## Credits

The original mod is by Fantom and Divvy, with new additions by Jonathan "GiefKid" Bowers. This fork preserves the full original commit history and
authorship, see the git log. I am more than happy to push this fork into the original mod, however [Fantom's Preview](https://github.com/Fantom-Balatro/Fantoms-Preview)
appears to not be active (no commits or maintainer response since Feb 2026, and multiple open unmerged PRs including one of my own back in June, [#14](https://github.com/Fantom-Balatro/Fantoms-Preview/pull/14))
