--- Original: Divvy's Simulation for Balatro - Engine.lua
--
-- The heart of this library: it replicates the game's score evaluation.

if not FN.SIM.run then
   function FN.SIM.run()
      local null_ret = {score = {min=0, exact=0, max=0}, dollars = {min=0, exact=0, max=0}}
      if #G.hand.highlighted < 1 then return null_ret end

      FN.SIM.init()

      FN.SIM.manage_state("SAVE")
      FN.SIM.update_state_variables()

      if not FN.SIM.simulate_blind_debuffs() then
         FN.SIM.simulate_joker_before_effects()
         FN.SIM.add_base_chips_and_mult()
         FN.SIM.simulate_blind_effects()
         FN.SIM.simulate_scoring_cards()
         FN.SIM.simulate_held_cards()
         FN.SIM.simulate_joker_global_effects()
         FN.SIM.simulate_consumable_effects()
         FN.SIM.simulate_deck_effects()
      else -- Only Matador at this point:
         FN.SIM.simulate_all_jokers(G.jokers, {debuffed_hand = true})
      end

      FN.SIM.manage_state("RESTORE")

      return FN.SIM.get_results()
   end

   function FN.SIM.init()
      -- Reset:
      FN.SIM.running = {
         min   = {chips = 0, mult = 0, dollars = 0},
         exact = {chips = 0, mult = 0, dollars = 0},
         max   = {chips = 0, mult = 0, dollars = 0},
         reps = 0
      }
      -- One entry per random mult trial (each Lucky Card, Misprint draw, etc.)
      -- for build_prob_percent. other_range_source gets set by any other mult range.
      FN.SIM.prob_trials = {}
      FN.SIM.other_range_source = false
      -- What else caused a range, for the tooltip (see FN.PRE.classify_range):
      -- The Hook's discards, jokers that go off your money (Bull, Bootstraps), and
      -- Lucky Cat (random, but not one of the prob_trials kinds)
      FN.SIM.hook_range_source = false
      -- Score for each pair The Hook could discard, for the % and sweep. nil if any pair
      -- has its own range or a held card is face down
      FN.SIM.hook_outcomes = nil
      FN.SIM.money_range_source = false
      FN.SIM.random_range_source = false
      FN.SIM.recognized_trial_in_progress = false
      -- Raised Fist's face-down range still sets other_range_source (so the Misprint
      -- sweep and % stay off), but it gets its own sweep. non_rf_range_source is set by
      -- every other mult range, rf_outcomes is the list from raised_fist_outcomes.
      FN.SIM.raised_fist_in_progress = false
      FN.SIM.non_rf_range_source = false
      FN.SIM.rf_outcomes = nil
      -- Lucky Card money rolls, one {p, amount} per roll (retriggers included). They only
      -- change the score through Bull/Bootstraps, see FN.PRE.money_mult_outcomes.
      FN.SIM.money_trials = {}
      FN.SIM.money_trial_in_progress = false
      -- Set by any other random money (Business Card, Reserved Parking...)
      FN.SIM.other_money_range = false
      -- Bootstraps' part of the mult range, times every xMult after it
      FN.SIM.money_mult_delta = nil
      FN.SIM.money_mult_in_progress = false
      -- Set when money doesn't change the score evenly per roll (Bull/Bootstraps below $0,
      -- a payout that isn't a multiple of Bootstraps' $5, a random xMult after Bootstraps)
      FN.SIM.money_nonlinear = false

      -- Fetch metadata about simulated play:
      local hand_name, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
      FN.SIM.env.scoring_name = hand_name

      -- Identify played cards and extract necessary data:
      FN.SIM.env.played_cards = {}
      FN.SIM.env.scoring_cards = {}
      local is_splash_joker = next(find_joker("Splash"))
      table.sort(G.hand.highlighted, function(a, b) return a.T.x < b.T.x end) -- Sorts by positional x-value to mirror card order!
      for _, card in ipairs(G.hand.highlighted) do
         local is_scoring = false
         for _, scoring_card in ipairs(scoring_hand) do
         -- Either card is scoring because it's part of the scoring hand,
         -- or there is Splash joker, or it's a Stone Card:
            if card.sort_id == scoring_card.sort_id
               or is_splash_joker
               or card.ability.effect == "Stone Card"
            then
               is_scoring = true
               break
            end
         end

         local card_data = FN.SIM.get_card_data(card)
         table.insert(FN.SIM.env.played_cards, card_data)
         if is_scoring then table.insert(FN.SIM.env.scoring_cards, card_data) end
      end

      -- Identify held cards and extract necessary data:
      -- Face-down cards are skipped so the preview can't leak them. hidden_held marks
      -- the result as a lower bound, and lets Blackboard/Raised Fist widen their max.
      FN.SIM.env.held_cards  = {}
      FN.SIM.env.hidden_held = false
      for _, card in ipairs(G.hand.cards) do
         -- Highlighted cards are simulated as played cards:
         if not card.highlighted then
            if FN.PRE.is_hidden(card) then
               FN.SIM.env.hidden_held = true
            else
               local card_data = FN.SIM.get_card_data(card)
               table.insert(FN.SIM.env.held_cards, card_data)
            end
         end
      end

      -- Extract necessary joker data:
      FN.SIM.env.jokers = {}
      for _, joker in ipairs(G.jokers.cards) do
         local joker_data = {
            -- P_CENTER keys for jokers have the form j_NAME, get rid of j_
            id = joker.config.center.key:sub(3, #joker.config.center.key),
            key = joker.config.center.key,
            -- original_mod is only set on jokers a mod added, not vanilla ones a mod
            -- took ownership of (see find_unknown_jokers)
            modded = joker.config.center.original_mod ~= nil,
            ability = copy_table(joker.ability),
            edition = copy_table(joker.edition),
            rarity = joker.config.center.rarity,
            debuff = joker.debuff
         }
         table.insert(FN.SIM.env.jokers, joker_data)
      end

      -- Extract necessary consumable data:
      FN.SIM.env.consumables = {}
      for _, consumable in ipairs(G.consumeables.cards) do
         local consumable_data = {
            -- P_CENTER keys have the form x_NAME, get rid of x_
            id = consumable.config.center.key:sub(3, #consumable.config.center.key),
            ability = copy_table(consumable.ability)
         }
         table.insert(FN.SIM.env.consumables, consumable_data)
      end

      -- Set extensible context template:
      FN.SIM.get_context = function(cardarea, args)
         local context = {
            cardarea = cardarea,
            full_hand = FN.SIM.env.played_cards,
            scoring_name = hand_name,
            scoring_hand = FN.SIM.env.scoring_cards,
            poker_hands = poker_hands
         }

         for k, v in pairs(args) do
            context[k] = v
         end

         return context
      end
   end

   function FN.SIM.get_card_data(card_obj)
      local ability = copy_table(card_obj.ability)
      -- Remember how much of ability.bonus comes from the enhancement, so set_ability
      -- can take it back off (eg. Midas Mask turning a Bonus card to Gold).
      -- Lives in .ability so the Hook snapshot/restore picks it up too.
      ability.center_bonus = (card_obj.config.center.config.bonus or 0)
      return {
         rank = card_obj.base.id,
         suit = card_obj.base.suit,
         base_chips = card_obj.base.nominal,
         ability = ability,
         edition = copy_table(card_obj.edition),
         seal = card_obj.seal,
         debuff = card_obj.debuff,
         lucky_trigger = {}
      }
   end

   function FN.SIM.get_results()
      local FNSR = FN.SIM.running

      local min_score   = math.floor(FNSR.min.chips   * FNSR.min.mult)
      local exact_score = math.floor(FNSR.exact.chips * FNSR.exact.mult)
      local max_score   = math.floor(FNSR.max.chips   * FNSR.max.mult)

      return {
         score   = {min = min_score,        exact = exact_score,        max = max_score},
         dollars = {min = FNSR.min.dollars, exact = FNSR.exact.dollars, max = FNSR.max.dollars},
         unknown_jokers = FN.SIM.find_unknown_jokers()
      }
   end

   -- Names of modded jokers with no simulate_ function (score might be off), or nil.
   -- Vanilla ones are skipped, lots have no function on purpose (Splash, Juggler...)
   function FN.SIM.find_unknown_jokers()
      local names, seen = {}, {}
      for _, joker in ipairs(FN.SIM.env.jokers) do
         if joker.modded and not joker.debuff and not seen[joker.key]
            and not FN.SIM.JOKERS["simulate_" .. joker.id]
         then
            seen[joker.key] = true
            local name = localize{type = 'name_text', set = 'Joker', key = joker.key}
            if not name or name == "ERROR" then name = joker.key end
            names[#names + 1] = name
         end
      end
      if #names == 0 then return nil end
      return names
   end

   --
   -- GAME STATE MANAGEMENT:
   --

   function FN.SIM.manage_state(save_or_restore)
      local FNSO = FN.SIM.orig

      if save_or_restore == "SAVE" then
         FNSO.random_data = copy_table(G.GAME.pseudorandom)
         FNSO.hand_data = copy_table(G.GAME.hands)
         return
      end

      if save_or_restore == "RESTORE" then
         G.GAME.pseudorandom = FNSO.random_data
         G.GAME.hands = FNSO.hand_data
         return
      end
   end

   function FN.SIM.update_state_variables()
      -- Increment poker hand played this run/round:
      local hand_info = G.GAME.hands[FN.SIM.env.scoring_name]
      hand_info.played = hand_info.played + 1
      hand_info.played_this_round = hand_info.played_this_round + 1
   end

   --
   -- MACRO LEVEL:
   --

   function FN.SIM.simulate_scoring_cards()
      for _, scoring_card in ipairs(FN.SIM.env.scoring_cards) do
         FN.SIM.simulate_card_in_context(scoring_card, G.play)
      end
   end

   function FN.SIM.simulate_held_cards()
      for _, held_card in ipairs(FN.SIM.env.held_cards) do
         FN.SIM.simulate_card_in_context(held_card, G.hand)
      end
      -- Face-down held cards aren't in env.held_cards, but Reserved Parking can still pay
      -- on them before the jokers score, so put that in the ceiling for Bull/Bootstraps
      if FN.SIM.env.hidden_held then
         FN.SIM.running.max.dollars = FN.SIM.running.max.dollars + FN.PRE.hidden_parking_dollars()
      end
   end

   function FN.SIM.simulate_joker_global_effects()
      for _, joker in ipairs(FN.SIM.env.jokers) do
         if not joker.debuff then
            if joker.edition then -- Foil and Holo:
               if joker.edition.chips then FN.SIM.add_chips(joker.edition.chips) end
               if joker.edition.mult  then FN.SIM.add_mult(joker.edition.mult) end
            end
         end

         FN.SIM.simulate_joker(joker, FN.SIM.get_context(G.jokers, {global = true}))

         -- Joker-on-joker effects (eg. Blueprint):
         FN.SIM.simulate_all_jokers(G.jokers, {other_joker = joker})

         if not joker.debuff then
            if joker.edition then -- Poly:
               if joker.edition.x_mult then FN.SIM.x_mult(joker.edition.x_mult) end
            end
         end
      end
   end

   function FN.SIM.simulate_consumable_effects()
      for _, consumable in ipairs(FN.SIM.env.consumables) do
         if consumable.ability.set == "Planet" and not consumable.debuff then
            if G.GAME.used_vouchers.v_observatory and consumable.ability.consumeable.hand_type == FN.SIM.env.scoring_name then
               FN.SIM.x_mult(G.P_CENTERS.v_observatory.config.extra)
            end
         end
      end
   end

   function FN.SIM.add_base_chips_and_mult()
      local played_hand_data = G.GAME.hands[FN.SIM.env.scoring_name]
      FN.SIM.add_chips(played_hand_data.chips)
      FN.SIM.add_mult(played_hand_data.mult)
   end

   function FN.SIM.simulate_joker_before_effects()
      for _, joker in ipairs(FN.SIM.env.jokers) do
         FN.SIM.simulate_joker(joker, FN.SIM.get_context(G.jokers, {before = true}))
      end
   end

   function FN.SIM.simulate_blind_effects()
      if G.GAME.blind.disabled then return end

      if G.GAME.blind.name == "The Flint" then
         local function flint(data)
            local half_chips = math.floor(data.chips/2 + 0.5)
            local half_mult = math.floor(data.mult/2 + 0.5)
            data.chips = FN.SIM.mod_chips(math.max(half_chips, 0))
            data.mult  = FN.SIM.mod_mult(math.max(half_mult, 1))
         end

         flint(FN.SIM.running.min)
         flint(FN.SIM.running.exact)
         flint(FN.SIM.running.max)
      else
         -- Other blinds do not impact scoring; refer to Blind:modify_hand(..)
      end
   end

   function FN.SIM.simulate_deck_effects()
      if G.GAME.selected_back.name == 'Plasma Deck' then
         local function plasma(data)
            local sum = data.chips + data.mult
            local half_sum = math.floor(sum/2)
            data.chips = FN.SIM.mod_chips(half_sum)
            data.mult = FN.SIM.mod_mult(half_sum)
         end

         plasma(FN.SIM.running.min)
         plasma(FN.SIM.running.exact)
         plasma(FN.SIM.running.max)
      else
         -- Other decks do not impact scoring; refer to Back:trigger_effect(..)
      end
   end

   function FN.SIM.simulate_blind_debuffs()
      local blind_obj = G.GAME.blind
      if blind_obj.disabled then return false end

      -- The following are part of Blind:press_play()

      if blind_obj.name == "The Hook" then
         -- press_play sets triggered, but debuff_hand clears it again before the jokers
         -- score (Hook's debuff = {} still counts), so Matador never pays here
         blind_obj.triggered = false

   local held = FN.SIM.env.held_cards
   local n = #held

   -- Each Hook pass reruns scoring, and scaling jokers / Hiker / lucky_trigger mutate
   -- the sim's copies, so reset them between passes or the score keeps climbing.
   -- Only swap the fields, scoring_cards shares tables with played_cards.
   local function snapshot_abilities(list)
      local snap = {}
      for i, cd in ipairs(list) do snap[i] = copy_table(cd.ability) end
      return snap
   end

   local pristine_jokers = snapshot_abilities(FN.SIM.env.jokers)
   local pristine_played = snapshot_abilities(FN.SIM.env.played_cards)
   local pristine_held   = snapshot_abilities(held)

   local function restore_sim_state()
      -- DNA adds its copy to the held list during a pass, take it back off
      for i = #held, n + 1, -1 do held[i] = nil end
      for i, joker in ipairs(FN.SIM.env.jokers) do
         joker.ability = copy_table(pristine_jokers[i])
      end
      for i, cd in ipairs(FN.SIM.env.played_cards) do
         cd.ability = copy_table(pristine_played[i])
         cd.lucky_trigger = {}
      end
      for i, cd in ipairs(held) do
         cd.ability = copy_table(pristine_held[i])
         cd.lucky_trigger = {}
      end
   end

   -- The Hook discards before the hand scores, so fire discard jokers first
   -- (Castle, Mail, Ramen, Hit the Road, Yorick)
   local function simulate_hook_discards(discarded_cards)
      for _, card in ipairs(discarded_cards) do
         FN.SIM.simulate_all_jokers(G.hand, {other_card = card, discard = true, full_hand = discarded_cards})
      end
   end

   -- One scoring pass with these held cards, after The Hook discards discarded_cards
   local function hook_probe(held_override, discarded_cards)
      restore_sim_state()
      FN.SIM.running.min   = {chips = 0, mult = 0, dollars = 0}
      FN.SIM.running.exact = {chips = 0, mult = 0, dollars = 0}
      FN.SIM.running.max   = {chips = 0, mult = 0, dollars = 0}
      if SP and SP._sim_running then
         SP._c_chips = 0; SP._c_mult = 0; SP._c_xmult = 1
         SP._j_chips = 0; SP._j_mult = 0; SP._j_xmult = 1
      end
      -- After the reset, so Mail-In money from these discards reaches Bull/Bootstraps
      simulate_hook_discards(discarded_cards)
      FN.SIM.env.held_cards = held_override
      FN.SIM.simulate_joker_before_effects()
      FN.SIM.add_base_chips_and_mult()
      FN.SIM.simulate_blind_effects()
      FN.SIM.simulate_scoring_cards()
      FN.SIM.simulate_held_cards()
      FN.SIM.simulate_joker_global_effects()
      FN.SIM.simulate_consumable_effects()
      FN.SIM.simulate_deck_effects()
      return FN.SIM.get_results()
   end

   -- Fast path: try with no held cards and with all of them. If both give the same
   -- score, held cards don't matter and we can skip the combination loop.
   -- Full-held runs last so running + SP state are left from that one.
   local res_none = hook_probe({}, held)
   local res_full = hook_probe(held, {})
   FN.SIM.env.held_cards = held  -- always restore

   if res_none.score.max == res_full.score.max
      and res_none.score.min == res_full.score.min then
      -- Held cards don't matter, use the full-held result
      FN.SIM.running.min = {chips = res_full.score.min, mult = 1, dollars = res_full.dollars.min}
      FN.SIM.running.max = {chips = res_full.score.max, mult = 1, dollars = res_full.dollars.max}
      return true
   end

   -- The Hook always discards min(2, n) cards (see Blind:press_play), so only
   -- try combos of that size. Smaller ones can't happen and inflate the max.
   local combinations = {}
   local k = math.min(2, n) -- number of cards The Hook will discard

   if k == 0 then
      table.insert(combinations, {})
   elseif k == 1 then
      for a = 1, n do
         table.insert(combinations, {a})
      end
   else -- k == 2
      for a = 1, n - 1 do
         for b = a + 1, n do
            table.insert(combinations, {a, b})
         end
      end
   end

   local min_score, max_score = math.huge, -math.huge
   local min_dollars, max_dollars = math.huge, -math.huge
   -- Keep SP breakdown from the max-score run only
   local best_sp_state = nil
   -- First combo's result, to tell if the discards actually change anything
   local first_res = nil
   -- Every pair is equally likely (The Hook picks 2 different cards at random)
   local outcomes = not FN.SIM.env.hidden_held and {} or nil

   for _, discard_idxs in ipairs(combinations) do
      -- Reset first so held_copy is clean too
      restore_sim_state()

      -- Deep copy held cards
      local held_copy = {}
      for i, card in ipairs(held) do
         held_copy[i] = copy_table(card)
      end

      -- Grab discarded cards before the indices get shifted by table.remove
      local discarded_cards = {}
      for _, idx in ipairs(discard_idxs) do
         discarded_cards[#discarded_cards + 1] = held[idx]
      end

      -- Remove discard cards from held_copy
      table.sort(discard_idxs, function(a, b) return a > b end)
      for _, idx in ipairs(discard_idxs) do
         table.remove(held_copy, idx)
      end

      local res = hook_probe(held_copy, discarded_cards)
      FN.SIM.env.held_cards = held
      -- Different discards giving different scores means The Hook matters
      if not first_res then
         first_res = res
      elseif res.score.min ~= first_res.score.min or res.score.max ~= first_res.score.max then
         FN.SIM.hook_range_source = true
      end
      if res.score.max > max_score then
         max_score = res.score.max
         -- Save SP state from the best run
         if SP and SP._sim_running then
            best_sp_state = {
               _c_chips = SP._c_chips, _c_mult = SP._c_mult, _c_xmult = SP._c_xmult,
               _j_chips = SP._j_chips, _j_mult = SP._j_mult, _j_xmult = SP._j_xmult,
            }
         end
      end
      min_score = math.min(min_score, res.score.min)
      min_dollars = math.min(min_dollars, res.dollars.min)
      max_dollars = math.max(max_dollars, res.dollars.max)
      if outcomes and res.score.min == res.score.max then
         outcomes[#outcomes + 1] = {score = res.score.min, p = 1 / #combinations}
      else
         outcomes = nil
      end
   end
   FN.SIM.hook_outcomes = outcomes

   -- Put back SP state from the best run
   if best_sp_state and SP and SP._sim_running then
      SP._c_chips = best_sp_state._c_chips; SP._c_mult = best_sp_state._c_mult; SP._c_xmult = best_sp_state._c_xmult
      SP._j_chips = best_sp_state._j_chips; SP._j_mult = best_sp_state._j_mult; SP._j_xmult = best_sp_state._j_xmult
   end

   -- Overwrite final min/max range based on permutations
   FN.SIM.running.min = {chips = min_score, mult = 1, dollars = min_dollars}
   FN.SIM.running.max = {chips = max_score, mult = 1, dollars = max_dollars}

   -- NOTE: FN.SIM.running.exact remains unset here; it's not relevant in this projection context
   return true -- Prevent default simulation since we’ve replaced it entirely
end

      if blind_obj.name == "The Tooth" then
         blind_obj.triggered = true
         FN.SIM.add_dollars((-1) * #FN.SIM.env.played_cards)
      end

      -- The following are part of Blind:debuff_hand(..)

      if blind_obj.name == "The Arm" then
         blind_obj.triggered = false

         local played_hand_name = FN.SIM.env.scoring_name
         if G.GAME.hands[played_hand_name].level > 1 then
            blind_obj.triggered = true
            -- NOTE: Important to save/restore G.GAME.hands here
            -- NOTE: Implementation mirrors level_up_hand(..)
            local played_hand_data = G.GAME.hands[played_hand_name]
            played_hand_data.level = math.max(1, played_hand_data.level - 1)
            played_hand_data.mult  = math.max(1, played_hand_data.s_mult  + (played_hand_data.level-1) * played_hand_data.l_mult)
            played_hand_data.chips = math.max(0, played_hand_data.s_chips + (played_hand_data.level-1) * played_hand_data.l_chips)
         end
         return false -- IMPORTANT: Avoid duplicate effects from Blind:debuff_hand() below
      end

      if blind_obj.name == "The Ox" then
         blind_obj.triggered = false

         if FN.SIM.env.scoring_name == G.GAME.current_round.most_played_poker_hand then
            blind_obj.triggered = true
            FN.SIM.add_dollars(-G.GAME.dollars)
         end
         return false -- IMPORTANT: Avoid duplicate effects from Blind:debuff_hand() below
      end

      return blind_obj:debuff_hand(G.hand.highlighted, FN.SIM.env.poker_hands, FN.SIM.env.scoring_name, true)
   end

   --
   -- MICRO LEVEL (CARDS):
   --

   function FN.SIM.simulate_card_in_context(card, cardarea)
      -- Reset and collect repetitions:
      FN.SIM.running.reps = 1
      if card.seal == "Red" then FN.SIM.add_reps(1) end
      FN.SIM.simulate_all_jokers(cardarea, {other_card = card, repetition = true})

      -- Apply effects:
      for _ = 1, FN.SIM.running.reps do
         FN.SIM.simulate_card(card, FN.SIM.get_context(cardarea, {}))
         FN.SIM.simulate_all_jokers(cardarea, {other_card = card, individual = true})
      end
   end

   function FN.SIM.simulate_card(card_data, context)
      -- Do nothing if debuffed:
      if card_data.debuff then return end

      if context.cardarea == G.play then
         -- Chips:
         if card_data.ability.effect == "Stone Card" then
            FN.SIM.add_chips(card_data.ability.bonus + (card_data.ability.perma_bonus or 0))
         else
            FN.SIM.add_chips(card_data.base_chips + card_data.ability.bonus + (card_data.ability.perma_bonus or 0))
         end

         -- Mult:
         if card_data.ability.effect == "Lucky Card" then
            -- Each Lucky Card is its own 1 in 5 roll (see prob_outcomes)
            table.insert(FN.SIM.prob_trials, {kind = "binomial_add", p = FN.SIM.trigger_probability(5)})
            FN.SIM.recognized_trial_in_progress = true
            local exact_mult, min_mult, max_mult = FN.SIM.get_probabilistic_extremes(pseudorandom("nope"), 5, card_data.ability.mult, 0)
            FN.SIM.add_mult(exact_mult, min_mult, max_mult)
            FN.SIM.recognized_trial_in_progress = false
            -- Careful not to overwrite `card_data.lucky_trigger` outright:
            if exact_mult > 0 then card_data.lucky_trigger.exact = true end
            if min_mult > 0 then card_data.lucky_trigger.min = true end
            if max_mult > 0 then card_data.lucky_trigger.max = true end
         else
            FN.SIM.add_mult(card_data.ability.mult)
         end

         -- XMult:
         if card_data.ability.x_mult > 1 then
            FN.SIM.x_mult(card_data.ability.x_mult)
         end

         -- Dollars:
         if card_data.seal == "Gold" then
            FN.SIM.add_dollars(3)
         end
         if card_data.ability.p_dollars > 0 then
            if card_data.ability.effect == "Lucky Card" then
               table.insert(FN.SIM.money_trials, {p = FN.SIM.trigger_probability(15), amount = card_data.ability.p_dollars})
               FN.SIM.money_trial_in_progress = true
               local exact_dollars, min_dollars, max_dollars = FN.SIM.get_probabilistic_extremes(pseudorandom("notthistime"), 15, card_data.ability.p_dollars, 0)
               FN.SIM.add_dollars(exact_dollars, min_dollars, max_dollars)
               FN.SIM.money_trial_in_progress = false
               -- Careful not to overwrite `card_data.lucky_trigger` outright:
               if exact_dollars > 0 then card_data.lucky_trigger.exact = true end
               if min_dollars > 0 then card_data.lucky_trigger.min = true end
               if max_dollars > 0 then card_data.lucky_trigger.max = true end
            else
               FN.SIM.add_dollars(card_data.ability.p_dollars)
            end
         end

      -- Edition:
         if card_data.edition then
            if card_data.edition.chips then FN.SIM.add_chips(card_data.edition.chips) end
            if card_data.edition.mult then FN.SIM.add_mult(card_data.edition.mult) end
            if card_data.edition.x_mult then FN.SIM.x_mult(card_data.edition.x_mult) end
         end

      elseif context.cardarea == G.hand then
         if card_data.ability.h_mult > 0 then
            FN.SIM.add_mult(card_data.ability.h_mult)
         end

         if card_data.ability.h_x_mult > 0 then
            FN.SIM.x_mult(card_data.ability.h_x_mult)
         end
      end
   end

   --
   -- MICRO LEVEL (JOKERS):
   --

   function FN.SIM.simulate_all_jokers(cardarea, context_args)
      for _, joker in ipairs(FN.SIM.env.jokers) do
         FN.SIM.simulate_joker(joker, FN.SIM.get_context(cardarea, context_args))
      end
   end

   function FN.SIM.simulate_joker(joker_obj, context)
      -- Do nothing if debuffed:
      if joker_obj.debuff then return end

      local joker_simulation_function = FN.SIM.JOKERS["simulate_" .. joker_obj.id]
      if joker_simulation_function then joker_simulation_function(joker_obj, context) end
   end

end
