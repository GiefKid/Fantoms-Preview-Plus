--- Original: Divvy's Preview for Balatro - Utils.lua
--
-- Utilities for checking states and formatting display.

function FN.PRE.is_enough_to_win(chips)
   if G.GAME.blind and FN.PRE.in_playable_state()
   then return (G.GAME.chips + chips >= G.GAME.blind.chips)
   else return false
   end
end

-- Short numbers for "min - max" ranges so both ends fit side by side.
-- M/B use 4 sig figs (1.234M, 12.34M, 123.4M), K uses 3 (3.12K, 32.1K, 321K).
-- K is only used when the "(NN%)" text needs the room (see FN.PRE.misprint_pct).
-- Past G.E_SWITCH_POINT (1e11) vanilla switches to e-notation, so we let it handle that.
-- G.E_SWITCH_POINT is only set once vanilla formats its first number, hence the "or".
local UNITS = {{1e9, "B"}, {1e6, "M"}, {1e3, "K"}}

local function fmt_compact(num, allow_k)
   if num < 0 then return "-" .. fmt_compact(-num, allow_k) end
   if num >= (G.E_SWITCH_POINT or 1e11) then
      return number_format(num) -- Default Balatro function, handles e-notation.
   end
   for _, u in ipairs(UNITS) do
      local mag, suffix = u[1], u[2]
      if num >= mag and (suffix ~= "K" or allow_k) then
         local scaled = num / mag
         local decimals = (suffix == "K") and 2 or 3
         if scaled >= 100 then decimals = decimals - 2
         elseif scaled >= 10 then decimals = decimals - 1 end
         return string.format("%." .. decimals .. "f%s", scaled, suffix)
      end
   end
   return number_format(math.floor(num)) -- Default Balatro function.
end

-- Single numbers use vanilla formatting, only ranges get shortened.
-- allow_k adds the K tier, pass it when the "(NN%)" text is shown too.
function FN.PRE.format_number(num, is_range, allow_k)
   if not num or type(num) ~= 'number' then return num or '' end
   if is_range then return fmt_compact(num, allow_k) end
   return number_format(num)
end

function FN.PRE.get_dollar_colour(n)
   if n == 0 then return HEX("7e7667")
   elseif n > 0 then return G.C.MONEY
   elseif n < 0 then return G.C.RED
   end
end

function FN.PRE.get_sign_str(n)
   if n >= 0 then return "+"
   else return "" -- Negative numbers already have a sign
   end
end


-- Binomial coefficient, n and k are always small so this is fine
local function choose(nn, kk)
   local r = 1
   for i = 1, kk do r = r * (nn - i + 1) / i end
   return r
end

-- Lucky Cards with Bull/Bootstraps. Only the number of mult hits (j) and money hits (m)
-- matter, so 5 Lucky Cards is 6*6 outcomes. Each $20 hit adds the same chips/mult.
-- Returns a list of {score, p}, or nil if anything else is making a range
function FN.PRE.money_mult_outcomes()
   local FNSR = FN.SIM.running
   local money, trials = FN.SIM.money_trials, FN.SIM.prob_trials
   if not FN.SIM.money_range_source or #money == 0 then return nil end
   if FN.SIM.other_range_source or FN.SIM.other_money_range or FN.SIM.money_nonlinear then return nil end
   if G.GAME.modifiers.chips_dollar_cap then return nil end
   -- Hook passes rerun scoring without clearing the trial lists
   if G.GAME.blind.name == "The Hook" and not G.GAME.blind.disabled then return nil end

   local q, amount = money[1].p, money[1].amount
   for _, t in ipairs(money) do
      if t.p ~= q or t.amount ~= amount then return nil end
   end
   local p = trials[1] and trials[1].p
   for _, t in ipairs(trials) do
      if t.kind ~= "binomial_add" or t.p ~= p then return nil end
   end
   if q <= 0 or q >= 1 then return nil end
   if p and (p <= 0 or p >= 1) then return nil end

   local k, km = #trials, #money
   -- Bull alone doesn't set money_mult_delta
   local dm = FN.SIM.money_mult_delta or 0
   local lucky_span = (FNSR.max.mult - FNSR.min.mult) - dm
   local chip_step = (FNSR.max.chips - FNSR.min.chips) / km

   local outcomes = {}
   for m = 0, km do
      local pm = choose(km, m) * (q ^ m) * ((1 - q) ^ (km - m))
      local chips_m = FNSR.min.chips + m * chip_step
      for j = 0, k do
         local pj = (k > 0) and choose(k, j) * (p ^ j) * ((1 - p) ^ (k - j)) or 1
         local mult = FNSR.min.mult + ((k > 0) and lucky_span * j / k or 0) + dm * m / km
         outcomes[#outcomes + 1] = {score = math.floor(chips_m * mult), p = pm * pj}
      end
   end
   return outcomes
end

-- Every score the hand could get and its chance, from the random trials the sim saw
-- (FN.SIM.prob_trials): uniform (Misprint), binomial_add (Lucky), binomial_mult
-- (Bloodstone, LGG), single_trial (Space). Mult (and chips for Space) moves the same
-- amount per hit, so the min and max are enough to get every score in between.
-- nil if anything else is making the range, or the trials are mixed kinds or odds.
local function prob_outcomes(data)
   if data.held_bonus_applied or data.score.min == data.score.max then return nil end
   if FN.SIM.hook_outcomes then return FN.SIM.hook_outcomes end
   -- Money changing the score is only handled for Lucky Cards
   if FN.SIM.money_range_source then return FN.PRE.money_mult_outcomes() end
   if FN.SIM.other_range_source then return nil end

   local trials = FN.SIM.prob_trials
   if #trials == 0 then return nil end
   local t1 = trials[1]
   for _, t in ipairs(trials) do
      if t.kind ~= t1.kind or t.p ~= t1.p or t.span ~= t1.span then return nil end
   end

   local FNSR = FN.SIM.running
   local chips0, mult0 = FNSR.min.chips, FNSR.min.mult
   local d_chips, d_mult = FNSR.max.chips - chips0, FNSR.max.mult - mult0
   -- Only Space Joker moves the chips too
   if t1.kind ~= "single_trial" and d_chips ~= 0 then return nil end

   local outcomes = {}
   if t1.kind == "uniform" then
      -- Misprint draws aren't 50/50 like the others. ways[t] = how many of the
      -- (span+1)^n rolls add up to t
      local n, span = #trials, t1.span
      local total = span * n
      if total < 1 then return nil end
      local ways = {[0] = 1}
      for _ = 1, n do
         local new_ways = {}
         for t, c in pairs(ways) do
            for d = 0, span do new_ways[t + d] = (new_ways[t + d] or 0) + c end
         end
         ways = new_ways
      end
      for t = 0, total do
         outcomes[#outcomes + 1] = {score = math.floor(chips0 * (mult0 + d_mult * t / total)),
                                    p = ways[t] / (span + 1) ^ n}
      end
   else
      local k, p = #trials, t1.p
      if p <= 0 or p >= 1 then return nil end
      -- Bloodstone and LGG multiply on each hit, so mult goes up by the same ratio each time
      local ratio
      if t1.kind == "binomial_mult" then
         if mult0 <= 0 then return nil end
         ratio = (FNSR.max.mult / mult0) ^ (1 / k)
      end
      for j = 0, k do
         local chips, mult = chips0, mult0 + d_mult * j / k
         if ratio then mult = mult0 * ratio ^ j end
         if t1.kind == "single_trial" then chips = chips0 + d_chips * j / k end
         outcomes[#outcomes + 1] = {score = math.floor(chips * mult),
                                    p = choose(k, j) * (p ^ j) * ((1 - p) ^ (k - j))}
      end
   end
   return outcomes
end

-- Misprint sweep: cycle the left number through every score in between (min and max are
-- already shown). Works for anything prob_outcomes handles, nil otherwise.
function FN.PRE.build_misprint_sweep(data)
   local outcomes = data and prob_outcomes(data)
   if not outcomes then return nil end
   local seen, values = {}, {}
   for _, o in ipairs(outcomes) do
      if o.score > data.score.min and o.score < data.score.max and not seen[o.score] then
         seen[o.score] = true
         values[#values + 1] = o.score
      end
   end
   if #values == 0 then return nil end
   table.sort(values)
   return {values = values, start_time = G.TIMERS.REAL}
end

-- Chance to pass as the text inside "(NN%)". nil when it can't fail or can't pass (the
-- color already says so), "<1" / ">99" when it rounds to 0 or 100 but isn't.
-- The small margin is for float sums that should be exactly 0 or 1.
function FN.PRE.pct_text(passing)
   if passing <= 1e-9 or passing >= 1 - 1e-9 then return nil end
   local pct = math.floor(passing * 100 + 0.5)
   if pct <= 0 then return "<1" end
   if pct >= 100 then return ">99" end
   return pct
end

-- % chance the hand beats the blind, nil if prob_outcomes can't explain the range
function FN.PRE.build_prob_percent(data, needed)
   local outcomes = data and prob_outcomes(data)
   if not outcomes then return nil end
   local passing = 0
   for _, o in ipairs(outcomes) do
      if o.score >= needed then passing = passing + o.p end
   end
   return FN.PRE.pct_text(passing)
end

-- Raised Fist with face-down held cards, sweeps every mult it could give with the rank
-- ("(9)", "(10-K)", "(D)"). Same trick as Misprint. nil if anything else makes a range
function FN.PRE.build_raised_fist_sweep(data)
   if not (data and data.rf_outcomes) or data.held_extra_spread then return nil end
   if FN.SIM.non_rf_range_source or FN.SIM.money_range_source or #FN.SIM.prob_trials > 0 then return nil end

   local FNSR = FN.SIM.running
   if FNSR.min.chips ~= FNSR.max.chips then return nil end

   -- Lowest outcome is the hold. The highest is already on the right side but the sweep
   -- goes through it too, otherwise its label never shows and the last rank looks skipped.
   local outcomes = data.rf_outcomes
   local n = #outcomes
   if n < 2 then return nil end

   local v_lo, v_hi = outcomes[1].mult, outcomes[n].mult
   local chips, mult_lo, mult_hi = FNSR.min.chips, data.rf_mult_lo, data.rf_mult_hi
   local values, labels = {}, {}
   for i = 2, n do
      local mult_i = mult_lo + (mult_hi - mult_lo) * ((outcomes[i].mult - v_lo) / (v_hi - v_lo))
      values[#values + 1] = math.floor(chips * mult_i)
      labels[#labels + 1] = outcomes[i].label
   end

   return {values = values, labels = labels, hold_label = outcomes[1].label, start_time = G.TIMERS.REAL}
end

-- Hold on the min for 1s, sweep the rest over 2s, loop. Real time so game speed doesn't matter.
-- Returns the score and its label (only Raised Fist has labels)
function FN.PRE.misprint_sweep_value(sweep, min_score)
   if not sweep then return min_score end
   local t = (G.TIMERS.REAL - sweep.start_time) % 3
   if t < 1 then return min_score, sweep.hold_label end
   local idx = math.min(#sweep.values, math.floor((t - 1) / 2 * #sweep.values) + 1)
   return sweep.values[idx], sweep.labels and sweep.labels[idx]
end
