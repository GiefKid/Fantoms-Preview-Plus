--- Original: Divvy's Preview for Balatro - Core.lua

if SMODS and SMODS.current_mod then
	SMODS.Atlas({
		key = "modicon",
		path = "icon.png",
		px = 32,
		py = 32,
	})

	-- Just adds a settings gear in the SMODS mods list. The mod doesn't need SMODS,
	-- without it the settings stay at their defaults (see InitPreview.lua).
	SMODS.current_mod.config_tab = FN.get_preview_settings_page
end

-- The functions responsible for running the simulation at appropriate times;
-- ie. whenever the player modifies card selection or card order.

-- Face-down cards never go into the sim so the preview can't leak them.
-- sprite_facing too, Card:flip() sets facing right away but the sprite flips mid-animation.
-- FN.PRE.reveal skips this for one run (ScorePreview's run_hand_sim, deck cards are face-down)
function FN.PRE.is_hidden(card)
   if FN.PRE.reveal then return false end
   return card.facing == "back" or card.sprite_facing == "back"
end

local function any_hidden(cards)
   for _, card in ipairs(cards) do
      if FN.PRE.is_hidden(card) then return true end
   end
   return false
end

-- A selected face-down card: the hand itself cannot be determined.
function FN.PRE.hidden_selected() return any_hidden(G.hand.highlighted) end

-- A face-down joker: the joker order cannot be determined.
function FN.PRE.hidden_jokers() return any_hidden(G.jokers.cards) end

-- Face-down cards held but not selected. These get left out of the sim instead of
-- blacking out the preview (see env.held_cards in EngineSimulate.lua).
function FN.PRE.hidden_held_count()
   local n = 0
   for _, card in ipairs(G.hand.cards) do
      if not card.highlighted and FN.PRE.is_hidden(card) then n = n + 1 end
   end
   return n
end

-- "?" tacked onto every number when an unknown modded joker is in play
function FN.PRE.unknown_suffix(data)
   return (data and data.unknown_jokers) and "?" or ""
end

local function is_redseal(card) return card.seal == "Red" end
local function is_steel(card) return card.ability.h_x_mult > 0 end
local function is_king(card) return card:get_id() == 13 and not card.debuff end
local function is_queen(card) return card:get_id() == 12 and not card.debuff end
local function is_face(card) return card:is_face() end

-- Could this card be one of the face-down held cards? Anything face down or still in
-- the deck. Face-down cards never count as seen, otherwise the preview changing would
-- give away what they are.
local function is_unseen(card) return card.facing == "back" or card.area == G.deck end

local function count_unseen(predicate)
   local n = 0
   for _, card in ipairs(G.playing_cards) do
      if is_unseen(card) and predicate(card) then n = n + 1 end
   end
   return n
end

-- Splits hidden slots into Red Seal matches and plain matches (Red Seal first, it's worth
-- more). Each effect gets the full hidden_n since one card can be both a King and Steel.
local function bounded_pool(hidden_n, predicate)
   local k_red   = math.min(hidden_n, count_unseen(function(c) return predicate(c) and is_redseal(c) end))
   local k_plain = math.min(hidden_n - k_red, count_unseen(function(c) return predicate(c) and not is_redseal(c) end))
   return k_red, k_plain
end

-- Stone cards (and modded no-rank cards). Raised Fist skips these, it doesn't count them as 0.
local function is_no_rank(card)
   if SMODS and SMODS.has_no_rank then return SMODS.has_no_rank(card) end
   return card.ability.effect == "Stone Card"
end

local RANK_LABELS = {[11] = "J", [12] = "Q", [13] = "K", [14] = "A"}
local function rank_label(r) return RANK_LABELS[r] or tostring(r) end

-- Every mult Raised Fist could give with face-down cards held, low to high ({mult, label}).
-- known = lowest face-up ranked held card (or nil). Only uses ranks that still have an unseen card.
-- 0 mult is labeled D (lowest could be debuffed) or S (every held card could be Stone)
function FN.PRE.raised_fist_outcomes(known, hidden_n)
   local cap = known and known.rank or 14
   local groups = {}
   local function add(mult, r)
      local g = groups[mult]
      if g then
         g.lo, g.hi = math.min(g.lo, r), math.max(g.hi, r)
      else
         groups[mult] = {lo = r, hi = r}
      end
   end

   if known and not known.debuff then add(2 * known.base_chips, known.rank) end
   for _, card in ipairs(G.playing_cards) do
      if is_unseen(card) and not card.debuff and not is_no_rank(card) and card.base.id <= cap then
         add(2 * card.base.nominal, card.base.id)
      end
   end

   local out = {}
   local debuff_zero = (known and known.debuff)
      or count_unseen(function(c) return c.debuff and not is_no_rank(c) and c.base.id <= cap end) > 0
   if debuff_zero then
      out[1] = {mult = 0, label = "D"}
   elseif not known and count_unseen(is_no_rank) >= hidden_n then
      out[1] = {mult = 0, label = "S"}
   end

   local mults = {}
   for m in pairs(groups) do mults[#mults + 1] = m end
   table.sort(mults)
   for _, m in ipairs(mults) do
      local g = groups[m]
      local label = (g.lo == g.hi) and rank_label(g.lo) or (rank_label(g.lo) .. "-" .. rank_label(g.hi))
      out[#out + 1] = {mult = m, label = label}
   end
   return out
end

-- A face-up held card Raised Fist can fire on. Same check as simulate_raised_fist.
local function has_known_ranked_held()
   for _, card in ipairs(FN.SIM.env.held_cards) do
      if card.ability.effect ~= "Stone Card" then return true end
   end
   return false
end

-- The jokers that actually act, with Blueprint/Brainstorm swapped for whatever they end
-- up copying (copies of copies too). Same rules as the game: Blueprint copies its right
-- neighbor, Brainstorm the leftmost joker, and a debuffed joker anywhere in the chain or
-- a target that isn't blueprint_compat means nothing.
local function acting_jokers()
   local jokers = G.jokers.cards
   local function resolve(i, visited)
      local joker = jokers[i]
      if not joker or visited[i] or joker.debuff then return nil end
      visited[i] = true
      local name = joker.ability.name
      if name == "Blueprint" then return resolve(i + 1, visited) end
      if name == "Brainstorm" then return resolve(1, visited) end
      return joker
   end
   local out = {}
   for i, joker in ipairs(jokers) do
      local target = resolve(i, {})
      local is_copy = target ~= nil and target ~= joker
      if target and (not is_copy or target.config.center.blueprint_compat) then
         out[#out + 1] = target
      end
   end
   return out
end

-- How many times each held card fires: once, +1 per Mime (copies too), +1 more with a
-- Red Seal. Returns triggers for a Red Seal card and for a plain one.
local function held_triggers()
   local mimes = 0
   for _, joker in ipairs(acting_jokers()) do
      if joker.ability.name == "Mime" then mimes = mimes + 1 end
   end
   return 2 + mimes, 1 + mimes
end

-- Most Reserved Parking could pay out on the face-down held cards (Red Seal pays twice).
-- The sim adds this to the ceiling money in simulate_held_cards, since Parking pays
-- before the jokers score and Bull/Bootstraps count it.
function FN.PRE.hidden_parking_dollars()
   local hidden_n = FN.PRE.hidden_held_count()
   if hidden_n == 0 then return 0 end
   local dollars = 0
   local t_red, t_plain = held_triggers()
   for _, joker in ipairs(acting_jokers()) do
      if joker.ability.name == "Reserved Parking" then
         local reward = joker.ability.extra.dollars
         local kr, kp = bounded_pool(hidden_n, is_face)
         dollars = dollars + reward * (t_red * kr + t_plain * kp)
      end
   end
   return dollars
end

-- Most the hidden held cards could add (Steel, Baron, Shoot the Moon, Parking, Raised Fist).
-- dollars is already in the sim's max (see simulate_held_cards), it's only here so the
-- caller knows a hidden card mattered. other_spread = anything besides Raised Fist.
function FN.PRE.held_card_max_bonus()
   local bonus = {xmult = 1, add_mult = 0, floor_mult = 0, dollars = 0}
   local hidden_n = FN.PRE.hidden_held_count()
   if hidden_n == 0 then return bonus end
   bonus.dollars = FN.PRE.hidden_parking_dollars()

   -- Mime retriggers held cards, so each one can fire more than once
   local t_red, t_plain = held_triggers()

   local k_red, k_plain = bounded_pool(hidden_n, is_steel)
   bonus.xmult = G.P_CENTERS.m_steel.config.h_x_mult ^ (t_red * k_red + t_plain * k_plain)

   local rf_count = 0
   for _, joker in ipairs(acting_jokers()) do
      if joker.ability.name == "Baron" then
         local kr, kp = bounded_pool(hidden_n, is_king)
         bonus.xmult = bonus.xmult * joker.ability.extra ^ (t_red * kr + t_plain * kp)

      elseif joker.ability.name == "Shoot the Moon" then
         local kr, kp = bounded_pool(hidden_n, is_queen)
         bonus.add_mult = bonus.add_mult + joker.ability.extra * (t_red * kr + t_plain * kp)

      elseif joker.ability.name == "Raised Fist" and not has_known_ranked_held() then
         rf_count = rf_count + 1
      end
   end
   bonus.other_spread = bonus.xmult > 1 or bonus.add_mult > 0

   -- Every Raised Fist (copies too) fires on the same lowest card, so it's one outcome
   -- list times however many there are (and again for each Mime)
   if rf_count > 0 then
      rf_count = rf_count * t_plain
      local outcomes = FN.PRE.raised_fist_outcomes(nil, hidden_n)
      if #outcomes > 0 then
         bonus.rf_outcomes = outcomes
         bonus.floor_mult = rf_count * outcomes[1].mult
         bonus.add_mult = bonus.add_mult + rf_count * outcomes[#outcomes].mult
      end
   end
   return bonus
end

-- States where G.hand is the real hand and worth previewing. Tarot/Spectral packs let
-- you select hand cards as targets so they count, the other packs don't.
function FN.PRE.in_playable_state()
   return G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.DRAW_TO_HAND
      or G.STATE == G.STATES.PLAY_TAROT
      or G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK
end

-- Why the score is a range, for the tooltip: "hook", "money", "mixed", "misprint", "random"
-- Run it right after FN.SIM.run, ScorePreview's sims reuse the same flags
function FN.PRE.classify_range(data)
   if not (data and data.score) or data.score.min == data.score.max then return nil end
   if FN.SIM.hook_range_source then return "hook" end

   local trials = FN.SIM.prob_trials
   if #trials == 0 and FN.SIM.money_range_source then return "money" end
   if #trials > 0 then
      -- Different kinds or chances can't be combined (same checks as prob_outcomes)
      local t1 = trials[1]
      for _, t in ipairs(trials) do
         if t.kind ~= t1.kind or t.p ~= t1.p or t.span ~= t1.span then return "mixed" end
      end
      -- A random range the trials don't cover (eg. Lucky Cat off Lucky Card triggers)
      if FN.SIM.random_range_source or FN.SIM.non_rf_range_source then return "mixed" end
      -- Money on top of the rolls, only handled for Lucky Cards (see money_mult_outcomes)
      if FN.SIM.money_range_source and not FN.PRE.money_mult_outcomes() then return "mixed" end
      if t1.kind == "uniform" then return "misprint" end
   end
   return "random"
end

function FN.PRE.simulate()
   if not FN.PRE.in_playable_state()
   then return {score = {min = 0, exact = 0, max = 0}, dollars = {min = 0, exact = 0, max = 0}}
   end

   -- Only with a selection, so it doesn't flash "??????" while cards are drawn face-down
   if #G.hand.highlighted > 0 and (FN.PRE.hidden_selected() or FN.PRE.hidden_jokers())
   then return nil end

   local data = FN.SIM.run()
   data.range_cause = FN.PRE.classify_range(data)

   -- Held cards were left out, so the floor is right but the ceiling might not be.
   -- (Blackboard handles env.hidden_held on its own in Jokers/_Vanilla.lua)
   -- Needs the highlighted check, FN.SIM.run doesn't rebuild env with nothing selected
   -- so env.hidden_held could be stale.
   if #G.hand.highlighted > 0 and FN.SIM.env.hidden_held then
      -- Uses the unfloored running totals so rounding twice doesn't skew the bounds.
      local FNSR = FN.SIM.running
      local b = FN.PRE.held_card_max_bonus()
      -- Turns off the Misprint sweep, the extra spread is from hidden cards.
      -- Only if a hidden card could actually change something.
      data.held_bonus_applied = b.xmult > 1 or b.add_mult > 0 or b.floor_mult > 0 or b.dollars > 0
         or b.rf_outcomes ~= nil

      -- For build_raised_fist_sweep, rf_mult_lo/hi = final mult at lowest/highest outcome
      data.held_extra_spread = b.other_spread
      data.rf_outcomes = b.rf_outcomes or FN.SIM.rf_outcomes
      if b.rf_outcomes then
         data.rf_mult_lo = FNSR.min.mult + b.floor_mult
         data.rf_mult_hi = FNSR.max.mult + b.add_mult
      else
         data.rf_mult_lo = FNSR.min.mult
         data.rf_mult_hi = FNSR.max.mult
      end

      if b.xmult > 1 or b.add_mult > 0 then
         data.score.max = math.floor(FNSR.max.chips * (FNSR.max.mult + b.add_mult) * b.xmult)
      end
      if b.floor_mult > 0 then
         data.score.min = math.floor(FNSR.min.chips * (FNSR.min.mult + b.floor_mult))
      end
   end

   return data
end

--
-- SIMULATION UPDATE ADVICE:
--

-- Blind progress used for the colors (FN.PRE.pace). hands_left and G.GAME.chips change
-- during the scoring animation, so reading them live would recolor the preview mid-hand.
-- Only refreshed in playable states.
function FN.PRE.snapshot_pace()
   if not FN.PRE.in_playable_state() then return end

   local blind_chips = G.GAME.blind.chips
   if blind_chips <= 0 then FN.PRE.pace = nil; return end

   FN.PRE.pace = {
      remaining = math.max(0, blind_chips - G.GAME.chips),
      hands     = math.max(1, G.GAME.current_round.hands_left),
   }
end

-- Rebuilds the Misprint sweep and the "(NN%)" text. Both settings are on by default,
-- with them off these stay nil and you just get the plain range.
-- Called from sim_func and from the settings toggles so changes show up right away.
function FN.PRE.update_prob_state()
   -- nil unless the range comes from Misprint (or Raised Fist) alone
   FN.PRE.misprint_sweep = G.SETTINGS.FN.range_animation
      and (FN.PRE.build_misprint_sweep(FN.PRE.data) or FN.PRE.build_raised_fist_sweep(FN.PRE.data)) or nil
   FN.PRE.misprint_last_shown = nil
   FN.PRE.sweep_last_label = nil
   -- Works for any single chance source, not just Misprint (see build_prob_percent)
   FN.PRE.misprint_pct = (G.SETTINGS.FN.prob_percentage and FN.PRE.pace)
      and FN.PRE.build_prob_percent(FN.PRE.data, FN.PRE.pace.remaining) or nil
end

function FN.PRE.add_update_event(trigger)
   function sim_func()
      -- Don't recompute while a hand is scoring (cards and jokers are mid-animation),
      -- just keep the last number up. See fn_pre_score_UI_set.
      if G.STATE == G.STATES.HAND_PLAYED then return true end
      FN.PRE.data = FN.PRE.simulate()
      FN.PRE.snapshot_pace()
      FN.PRE.update_prob_state()
      return true
   end
   G.E_MANAGER:add_event(Event({trigger = trigger, func = sim_func}))
end

-- show_preview from the current highlights. Planets don't need a selection, so it can be
-- left over from the last hand and show "0" (the hooks below use it too).
function FN.PRE.rederive_show_preview()
   FN.PRE.show_preview = FN.PRE.auto_calculate and G.hand ~= nil and #G.hand.highlighted > 0
end

-- Update simulation after a consumable (eg. Tarot, Planet) is used:
local orig_use = Card.use_consumeable
function Card:use_consumeable(area, copier)
   orig_use(self, area, copier)
   FN.PRE.rederive_show_preview()
   FN.PRE.add_update_event("immediate")
end

-- Update simulation after card selection changed:
local orig_hl = CardArea.parse_highlighted
function CardArea:parse_highlighted()
   orig_hl(self)
   FN.PRE.rederive_show_preview()
   FN.PRE.add_update_event("immediate")
end

-- use_consumeable runs synchronously, so the check above still sees the Tarot's target
-- cards selected. They get unhighlighted in a later event, usually still in PLAY_TAROT,
-- and vanilla unhighlight_all only calls parse_highlighted in SELECTING_HAND. Without
-- this show_preview gets stuck true with an old number.
local orig_unhighlight_all = CardArea.unhighlight_all
function CardArea:unhighlight_all()
   orig_unhighlight_all(self)
   if self == G.hand then
      FN.PRE.rederive_show_preview()
      FN.PRE.add_update_event("immediate")
   end
end

-- Update simulation after joker or consumable sold:
local orig_card_remove = Card.remove_from_area
function Card:remove_from_area()
   orig_card_remove(self)
   if self.ability.set == 'Joker' or self.ability.consumeable then
      FN.PRE.add_update_event("immediate")
   end
end

-- Update simulation after joker reordering:
local orig_update = CardArea.update
function CardArea:update(dt)
   orig_update(self, dt)
   FN.PRE.update_on_card_order_change(self)
end

function FN.PRE.update_on_card_order_change(cardarea)
   if #cardarea.cards == 0 or not FN.PRE.in_playable_state()
   then return end
   -- Important not to update on G.STATES.HAND_PLAYED, because it would reset the preview text!

   if (G.STATE == G.STATES.HAND_PLAYED) then return end

   local prev_order = nil
   if cardarea.config.type == 'joker' and cardarea.cards[1].ability.set == 'Joker' then
      if cardarea.cards[1].edition and cardarea.cards[1].edition.mp_phantom then
         return
      end
      -- Note that the consumables cardarea also has type 'joker' so must verify by checking first card.
      prev_order = FN.PRE.joker_order
   elseif cardarea.config.type == 'hand' then
      prev_order = FN.PRE.hand_order
   else
      return
   end

   -- Go through stored card IDs and check against current card IDs, in-order.
   -- If any mismatch occurs, toggle flag and update name for next time.
   local should_update = false
   if #cardarea.cards ~= #prev_order then
      prev_order = {}
   end
   for i, c in ipairs(cardarea.cards) do
      if c.sort_id ~= prev_order[i] then
         prev_order[i] = c.sort_id
         should_update = true
      end
   end

   if should_update then
      if cardarea.config.type == 'joker' or cardarea.cards[1].ability.set == 'Joker' then
         FN.PRE.joker_order = prev_order
      elseif cardarea.config.type == 'hand' then
         FN.PRE.hand_order = prev_order
      end
      -- Also runs on the new deal at the start of a round, otherwise show_preview can
      -- stay true from last round and show "0" on the new blind.
      FN.PRE.rederive_show_preview()
      FN.PRE.add_update_event("immediate")
   end
end

--
-- SIMULATION RESET ADVICE:
--

function FN.PRE.add_reset_event(trigger)
   function reset_func()
      -- Same freeze as sim_func. Return nil here so the event keeps polling until scoring
      -- is done. Returning true ends the event, so the reset never runs and the last
      -- hand's % sticks around in the shop.
      if G.STATE == G.STATES.HAND_PLAYED then return end
      FN.PRE.data = {score = {min = 0, exact = 0, max = 0}, dollars = {min = 0, exact = 0, max = 0}}
      FN.PRE.misprint_sweep = nil
      FN.PRE.misprint_last_shown = nil
      FN.PRE.sweep_last_label = nil
      FN.PRE.misprint_pct = nil
      return true
   end
   -- Has to be non-blocking since it can poll for a while. If it blocks, the vanilla
   -- events that move HAND_PLAYED on to ROUND_EVAL never run and the round softlocks.
   G.E_MANAGER:add_event(Event({trigger = trigger, func = reset_func, blocking = false, blockable = false}))
end

local orig_eval = G.FUNCS.evaluate_play
function G.FUNCS.evaluate_play(e)
   orig_eval(e)
   FN.PRE.add_reset_event("after")
end

-- Discards don't always go through parse_highlighted, so recheck show_preview here too
-- or the reset score shows up as "0" instead of blank.
local orig_discard = G.FUNCS.discard_cards_from_highlighted
function G.FUNCS.discard_cards_from_highlighted(e, is_hook_blind)
   orig_discard(e, is_hook_blind)
   if not is_hook_blind then
      FN.PRE.rederive_show_preview()
      FN.PRE.add_reset_event("immediate")
   end
end

--
-- USER INTERFACE ADVICE:
--

-- A Mr. Bones that already went off destroys itself, so find_joker won't see it.
function FN.PRE.owns_mr_bones()
   return next(find_joker("Mr. Bones")) ~= nil
end

-- Would scoring this on every hand left get the round to 25% of the blind?
-- Same check Mr. Bones uses in main.lua (full blind chips, not pace.remaining).
function FN.PRE.mr_bones_would_save(score, hands)
   local blind_chips = G.GAME.blind.chips
   if blind_chips <= 0 then return false end
   return (G.GAME.chips + score * hands) / blind_chips >= 0.25
end

-- Gold if it beats the blind, red if behind pace (orange if Mr. Bones saves you), else white.
-- Same colors as ScorePreview's average boxes. Returns color, should_juice
function FN.PRE.get_blind_colour(score)
   local p = FN.PRE.pace
   if not p then
      FN.PRE.snapshot_pace()
      p = FN.PRE.pace
   end
   if not (p and score) then return G.C.UI.TEXT_LIGHT, false end
   local remaining, hands = p.remaining, p.hands
   if score >= remaining then
      return G.C.MONEY, true
   elseif score < remaining / hands then
      if FN.PRE.owns_mr_bones() and FN.PRE.mr_bones_would_save(score, hands) then
         return G.C.FILTER, false
      end
      return G.C.HAND_LEVELS[6], false
   end
   return G.C.UI.TEXT_LIGHT, false
end

-- Add animation to preview text:
-- Also shown during HAND_PLAYED so the last number stays up while the hand scores
-- (playing a hand clears the highlights, so show_preview alone would blank it).
function G.FUNCS.fn_pre_score_UI_set(e)
   local should_show = FN.PRE.show_preview or G.STATE == G.STATES.HAND_PLAYED
   -- Dash separator: always white, visible only in range mode.
   if e.config.id == "fn_pre_dash" then
      -- Hide it during the Autocalculate flash, otherwise you get "Autocalculate On -"
      if SP and SP._auto_toggle_flash then
         if FN.PRE.text.score.dash ~= "" then
            FN.PRE.text.score.dash = ""
            e.config.object:update_text()
         end
         return
      end
      local in_scoring = FN.PRE.in_playable_state() or G.STATE == G.STATES.HAND_PLAYED
      local want = in_scoring and FN.PRE.data and should_show
                   and FN.PRE.data.score.min ~= FN.PRE.data.score.max
      local t = want and " - " or ""
      if FN.PRE.text.score.dash ~= t then
         FN.PRE.text.score.dash = t
         e.config.object:update_text()
      end
      e.config.object.colours = {G.C.UI.TEXT_LIGHT}
      return
   end
   -- If GiefKid's Score Simulator mod (not yet public) is installed: flash "Autocalculate On/Off" for 2s when toggle is clicked.
   if SP and SP._auto_toggle_flash then
      local key = e.config.id:sub(-1)
      local flash_text = (key == 'l') and SP._auto_toggle_flash or " "
      if FN.PRE.text.score[key] ~= flash_text then
         FN.PRE.text.score[key] = flash_text
         e.config.object:update_text()
         G.FUNCS.text_super_juice(e, 0)
      end
      e.config.object.colours = {G.C.UI.TEXT_LIGHT}
      return
   end
   if not (FN.PRE.in_playable_state() or G.STATE == G.STATES.HAND_PLAYED) then
      if FN.PRE.text.score[e.config.id:sub(-1)] ~= " " then
         FN.PRE.text.score[e.config.id:sub(-1)] = " "
         e.config.object:update_text()
         G.FUNCS.text_super_juice(e, 0)
         e.config.object.colours = {G.C.UI.TEXT_LIGHT}
      end
      return
   end
   local new_preview_text = ""
   -- Score shown by this element, used for its color (nil = nothing shown)
   local score_value = nil
   -- True while the Misprint sweep is changing the number, so it doesn't wobble every step
   local misprint_animating = false
   -- True on the first frame the sweep freezes for HAND_PLAYED, so the frozen number gets
   -- its wobble even though the text didn't change
   local sweep_just_froze = false
   if e.config.id == "fn_pre_l" and G.STATE ~= G.STATES.HAND_PLAYED then FN.PRE.sweep_frozen = false end
   if FN.PRE.data then
      -- Unknown modded jokers add "?" to each number
      local q = FN.PRE.unknown_suffix(FN.PRE.data)
      if should_show and FN.PRE.data.score.min ~= FN.PRE.data.score.max then
         -- Format as 'X - Y' :
         if e.config.id == "fn_pre_l" then
            -- Misprint sweep, cycles through every value Misprint could roll (see
            -- build_misprint_sweep). Holds the last value during HAND_PLAYED.
            local shown = FN.PRE.data.score.min
            if FN.PRE.misprint_sweep then
               if G.STATE ~= G.STATES.HAND_PLAYED then
                  shown = FN.PRE.misprint_sweep_value(FN.PRE.misprint_sweep, FN.PRE.data.score.min)
                  FN.PRE.misprint_last_shown = shown
                  misprint_animating = true
               else
                  shown = FN.PRE.misprint_last_shown or shown
               end
            end
            local frozen = FN.PRE.misprint_sweep ~= nil and G.STATE == G.STATES.HAND_PLAYED
            sweep_just_froze = frozen and not FN.PRE.sweep_frozen
            FN.PRE.sweep_frozen = frozen
            -- Shorten to K only if the "(NN%)" text needs the room (same check as
            -- fn_pre_pct_UI_set)
            new_preview_text = FN.PRE.format_number(shown, true, FN.PRE.has_side_text()) .. q
            score_value = shown
         elseif e.config.id == "fn_pre_r" then
            new_preview_text = FN.PRE.format_number(FN.PRE.data.score.max, true, FN.PRE.has_side_text()) .. q
            score_value = FN.PRE.data.score.max
         end
      else
         -- Format as single number:
         if e.config.id == "fn_pre_l" then
            if true then
               -- Spaces around number necessary to distinguish Min/Max text from Exact text,
               -- which is itself necessary to force a HUD update when switching between Min/Max and Exact.
               if should_show then
                  new_preview_text = " " .. FN.PRE.format_number(FN.PRE.data.score.min) .. q .. " "
                  score_value = FN.PRE.data.score.min
               else
                  new_preview_text = "  "
               end
               end
            else
               new_preview_text = ""
            end
         end
      else
         -- Face-down card or joker in play (tooltip explains, see fn_pre_score_tooltip_set)
         -- Spaces around number necessary to distinguish Min/Max text from Exact text, same as above ^
         if e.config.id == "fn_pre_l" then
            new_preview_text = " ?????? "
         else
            new_preview_text = ""
         end
      end

   -- Set the color every frame, otherwise an end whose number didn't change keeps an old color
   local colour, should_juice = G.C.UI.TEXT_LIGHT, false
   if score_value then colour, should_juice = FN.PRE.get_blind_colour(score_value) end
   e.config.object.colours = {colour}

   if (not FN.PRE.text.score[e.config.id:sub(-1)]) or new_preview_text ~= FN.PRE.text.score[e.config.id:sub(-1)] then
      FN.PRE.text.score[e.config.id:sub(-1)] = new_preview_text
      e.config.object:update_text()
      -- Wobble:
      -- (skipped during the Misprint sweep)
      if not G.TAROT_INTERRUPT_PULSE and not misprint_animating then
         G.FUNCS.text_super_juice(e, should_juice and 5 or 0)
      end
   elseif sweep_just_froze and not G.TAROT_INTERRUPT_PULSE then
      G.FUNCS.text_super_juice(e, should_juice and 5 or 0)
   end
end

-- True if something goes in the "(NN%)" slot, so the range gets shortened to K.
function FN.PRE.has_side_text()
   return FN.PRE.misprint_pct ~= nil or (FN.PRE.misprint_sweep ~= nil and FN.PRE.misprint_sweep.labels ~= nil)
end

-- "(NN%)" chance to pass. Its own element next to fn_pre_r so it stays white (see
-- InterfacePreview.lua). misprint_pct is already nil when it shouldn't show.
-- The Raised Fist sweep puts the rank for the current left number here instead ("(9)").
function G.FUNCS.fn_pre_pct_UI_set(e)
   local should_show = FN.PRE.show_preview or G.STATE == G.STATES.HAND_PLAYED
   local text = ""
   if should_show and FN.PRE.misprint_pct then
      text = " (" .. FN.PRE.misprint_pct .. "%" .. FN.PRE.unknown_suffix(FN.PRE.data) .. ")"
   elseif should_show and FN.PRE.misprint_sweep and FN.PRE.misprint_sweep.labels then
      -- Same freeze as the left number during HAND_PLAYED
      local label = FN.PRE.sweep_last_label
      if G.STATE ~= G.STATES.HAND_PLAYED then
         label = select(2, FN.PRE.misprint_sweep_value(FN.PRE.misprint_sweep, 0))
         FN.PRE.sweep_last_label = label
      end
      if label then text = " (" .. label .. ")" end
   end
   if FN.PRE.text.score.pct ~= text then
      FN.PRE.text.score.pct = text
      e.config.object:update_text()
   end
end

function G.FUNCS.fn_pre_dollars_UI_set(e)
   local new_preview_text = ""
   local new_colour = nil
   if FN.PRE.data then
      if true and (FN.PRE.data.dollars.min ~= FN.PRE.data.dollars.max) then
         if e.config.id == "fn_pre_dollars_top" then
            new_preview_text = " " .. FN.PRE.get_sign_str(FN.PRE.data.dollars.max) .. FN.PRE.data.dollars.max
            new_colour = FN.PRE.get_dollar_colour(FN.PRE.data.dollars.max)
         elseif e.config.id == "fn_pre_dollars_bot" then
            new_preview_text = " " .. FN.PRE.get_sign_str(FN.PRE.data.dollars.min) .. FN.PRE.data.dollars.min
            new_colour = FN.PRE.get_dollar_colour(FN.PRE.data.dollars.min)
         end
      else
         if e.config.id == "fn_pre_dollars_top" then
            local _data = (G.SETTINGS.FN.show_min_max) and FN.PRE.data.dollars.min or FN.PRE.data.dollars.exact

            new_preview_text = " " .. FN.PRE.get_sign_str(_data) .. _data
            new_colour = FN.PRE.get_dollar_colour(_data)
         else
            new_preview_text = ""
            new_colour = FN.PRE.get_dollar_colour(0)
         end
      end
   else
      new_preview_text = " +??"
      new_colour = FN.PRE.get_dollar_colour(0)
   end

   if (not FN.PRE.text.dollars[e.config.id:sub(-3)]) or new_preview_text ~= FN.PRE.text.dollars[e.config.id:sub(-3)] then
      FN.PRE.text.dollars[e.config.id:sub(-3)] = new_preview_text
      e.config.object.colours = {new_colour}
      e.config.object:update_text()
      if not G.TAROT_INTERRUPT_PULSE then e.config.object:pulse(0.25) end
   end
end
