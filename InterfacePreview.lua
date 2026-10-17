--- Original: Divvy's Preview for Balatro - Interface.lua
--
-- The user interface components that display simulation results.

-- Append node for preview text to the HUD:
local orig_hud = create_UIBox_HUD
function create_UIBox_HUD()
   local contents = orig_hud()
   
   local hand_text_area = FN.PRE.find_hand_text_area(contents)
   if not hand_text_area then return contents end
   table.insert(hand_text_area.nodes[1].nodes, FN.PRE.get_preview_container())

   return contents
end

function G.FUNCS.calculate_score_button()
   FN.PRE.auto_calculate = not FN.PRE.auto_calculate
   FN.PRE.rederive_show_preview()
   FN.PRE.add_update_event("immediate")
end

function G.FUNCS.calculate_score_button_UI_set(e)
   e.config.colour = FN.PRE.auto_calculate and G.C.RED or G.C.GREY
end

-- Only used without ScorePreview, since SP replaces get_calculate_score_button
function G.FUNCS.fn_calculate_score_button_text_UI_set(e)
   local t = FN.PRE.auto_calculate and "  Autocalculate On  " or "  Autocalculate Off  "
   if FN.PRE.text.button.label ~= t then
      FN.PRE.text.button.label = t
      e.config.object:update_text()
   end
end

function FN.PRE.get_preview_container()
   return {n=G.UIT.R, config={id = "fn_preview_container", align = "cm"}, nodes={
      {n=G.UIT.C, config={align = "cm"}, nodes={
         {n=G.UIT.R, config={id = "fn_pre_score_wrap", align = "cm", padding = 0.1}, nodes={
            FN.PRE.get_score_node()
         }},
         {n=G.UIT.R, config={id = "fn_calculate_score_button_wrap", align = "cm", padding = 0.1}, nodes={
            FN.PRE.get_calculate_score_button()
         }}
      }}
   }}
end

function FN.PRE.get_calculate_score_button()
   local button_node = {n=G.UIT.C, config={id = "calculate_score_button", button = "calculate_score_button", func = "calculate_score_button_UI_set", align = "cm", minh = 0.55, padding = 0.12, r = 0.02, colour = G.C.RED, hover = true, shadow = true}, nodes={
      {n=G.UIT.R, config={align = "cm"}, nodes={
         {n=G.UIT.O, config={id = "fn_calculate_score_button_text", func = "fn_calculate_score_button_text_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.button, ref_value = "label"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, scale = 0.4})}}
      }}
   }}

   -- Settings gear (ScorePreview has its own, it overrides this function).
   -- Needs SMODS for the gear sprite in the mod_tags atlas.
   if SMODS and SMODS.create_sprite and G.ASSET_ATLAS and G.ASSET_ATLAS['mod_tags'] then
      return {n=G.UIT.R, config={align = "cm"}, nodes={
         button_node,
         {n=G.UIT.B, config={w = 0.08, h = 0.1}},
         {n=G.UIT.C, config={button = "fn_pre_open_settings", align = "cm", minh = 0.55, minw = 0.55,
                              padding = 0.08, r = 0.02, colour = G.C.GREY, hover = true, shadow = true}, nodes={
            {n=G.UIT.O, config={object = SMODS.create_sprite(0, 0, 0.33, 0.33, 'mod_tags', {x = 2, y = 0})}}
         }},
      }}
   end

   return button_node
end

-- Gear button, same as ScorePreview's sp_open_settings
function G.FUNCS.fn_pre_open_settings(e)
   e.states.hover.is = false
   e.states.collide.is = false
   G.FUNCS.overlay_menu{definition = FN.PRE.build_settings_overlay()}
end

-- Same toggles as the config tab, with a title and back button
function FN.PRE.build_settings_overlay()
   local page = FN.get_preview_settings_page()
   local contents = {
      {n=G.UIT.R, config={align = "cm", padding = 0.1}, nodes={
         {n=G.UIT.T, config={text = "Fantom's Preview Settings", scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
      }},
   }
   for _, node in ipairs(page.nodes) do
      contents[#contents + 1] = node
   end
   return create_UIBox_generic_options({
      back_func = "exit_overlay_menu",
      contents = contents,
   })
end


-- Score tooltips. No title so there's no header row.
-- Don't put "" in text, localize_box crashes on it.
FN.PRE.FACE_DOWN_TOOLTIP = {
   text = {"Score is hidden when a selected card",
           "or any joker is face down"},
}

FN.PRE.HELD_BONUS_TOOLTIP = {
   text = {"A range is being shown because a face down",
           "card could increase/decrease the score"},
}

FN.PRE.PASS_CHANCE_TOOLTIP = {
   text = {"This is the probability that the score",
           "value will be enough to pass the blind"},
}

FN.PRE.MR_BONES_TOOLTIP = {
   text = {"This score is on-track such that",
           "you'll be saved by Mr. Bones"},
}

-- Ranges with no face-down cards or "(NN%)" involved, picked by data.range_cause
-- (see FN.PRE.classify_range)
FN.PRE.RANGE_TOOLTIPS = {
   hook = {
      text = {'Certain cards being discarded by "The Hook"',
              "could impact your score"},
   },
   money = {
      text = {"Money might increase, which could",
              "impact your score"},
   },
   mixed = {
      text = {"Multiple mixed probability sources force the",
              "preview to disable the animation/percentage --",
              "only the lowest and highest score can be",
              "reasonably deduced"},
   },
   misprint = {
      text = {"Misprint's Mult is random and produces",
              "a range of potential values"},
   },
   random = {
      text = {"The probability of certain effects",
              "triggering could impact your score"},
   },
}

-- The "mixed" text only makes sense if the animation or % would otherwise show
function FN.PRE.range_tooltip(data)
   local cause = data and data.range_cause
   if not cause then return nil end
   if cause == "mixed" and not (G.SETTINGS.FN.range_animation or G.SETTINGS.FN.prob_percentage) then
      cause = "random"
   end
   return FN.PRE.RANGE_TOOLTIPS[cause]
end

-- True if any number on screen is orange from Mr. Bones (see get_blind_colour),
-- including the in-between values of the range animation
function FN.PRE.showing_mr_bones(data)
   if not (data and data.score) then return false end
   local function orange(v) return v and FN.PRE.get_blind_colour(v) == G.C.FILTER end
   if orange(data.score.min) then return true end
   if data.score.min ~= data.score.max and orange(data.score.max) then
      return true
   end
   for _, v in ipairs(FN.PRE.misprint_sweep and FN.PRE.misprint_sweep.values or {}) do
      if orange(v) then return true end
   end
   return false
end

FN.PRE.MULTI_UNKNOWN_JOKER_TOOLTIP = {
   text = {"Multiple unknown jokers are detected and",
           "not programmed into Fantoms Preview, so",
           "this number may be inaccurate"},
}

-- Tooltip for data.unknown_jokers (see FN.SIM.find_unknown_jokers), nil if there aren't any.
-- ScorePreview uses this too.
function FN.PRE.unknown_joker_tooltip(data)
   local names = data and data.unknown_jokers
   if not names then return nil end
   if #names > 1 then return FN.PRE.MULTI_UNKNOWN_JOKER_TOOLTIP end
   return {text = {'The Joker "' .. names[1] .. '" is not',
                   "programmed into Fantoms Preview, so",
                   "this number may be inaccurate"}}
end

-- Move the tooltip to the right of the node. Centered ones run off the left edge of
-- the screen. Changing h_popup_config after it's built does nothing, so realign the popup.
function FN.PRE.align_tooltip_right(e)
   local pop = e.children and e.children.h_popup
   if pop then
      pop:set_alignment({major = e, type = 'cr', offset = {x = 0.1, y = 0}})
   end
end

-- Pick the tooltip for whatever's on screen, only one shows. Order:
--   "??????" face-down > unknown modded joker > face-down held cards >
--   "(NN%)" > Mr. Bones > why it's a range (Hook, money, mixed, Misprint, random)
-- Only "??????" shows while no number is up (same check as fn_pre_score_UI_set).
function G.FUNCS.fn_pre_score_tooltip_set(e)
   local tip = nil
   local showing = (FN.PRE.show_preview or G.STATE == G.STATES.HAND_PLAYED)
      and (FN.PRE.in_playable_state() or G.STATE == G.STATES.HAND_PLAYED)
   if FN.PRE.data == nil then
      tip = FN.PRE.FACE_DOWN_TOOLTIP
   elseif not showing then
      tip = nil
   elseif FN.PRE.data.unknown_jokers then
      tip = FN.PRE.unknown_joker_tooltip(FN.PRE.data)
   elseif FN.PRE.data.held_bonus_applied then
      tip = FN.PRE.HELD_BONUS_TOOLTIP
   elseif FN.PRE.misprint_pct then
      tip = FN.PRE.PASS_CHANCE_TOOLTIP
   elseif FN.PRE.showing_mr_bones(FN.PRE.data) then
      tip = FN.PRE.MR_BONES_TOOLTIP
   else
      tip = FN.PRE.range_tooltip(FN.PRE.data)
   end

   if tip then
      e.config.on_demand_tooltip = tip
      FN.PRE.align_tooltip_right(e)
   elseif e.config.on_demand_tooltip then
      -- Clear h_popup too or the old tooltip can stay stuck on screen
      e.config.on_demand_tooltip = nil
      e.config.h_popup = nil
   end
end

function FN.PRE.get_score_node()
   local text_scale = nil
   if true then text_scale = 0.5
   else text_scale = 0.75 end

   -- Needs can_collide or hover never fires and the tooltip won't show
   return {n = G.UIT.C, config = {id = "fn_pre_score", align = "cm", can_collide = true,
                                  func = "fn_pre_score_tooltip_set",
                                  on_demand_tooltip = FN.PRE.FACE_DOWN_TOOLTIP}, nodes={
              {n=G.UIT.O, config={id = "fn_pre_l",    func = "fn_pre_score_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.score, ref_value = "l"}},    colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
              {n=G.UIT.O, config={id = "fn_pre_dash", func = "fn_pre_score_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.score, ref_value = "dash"}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
              {n=G.UIT.O, config={id = "fn_pre_r",    func = "fn_pre_score_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.score, ref_value = "r"}},    colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
              -- Chance to pass (NN%). Has to be its own DynaText, a second string
              -- segment on fn_pre_r doesn't get drawn.
              {n=G.UIT.O, config={id = "fn_pre_pct",  func = "fn_pre_pct_UI_set",   object = DynaText({string = {{ref_table = FN.PRE.text.score, ref_value = "pct"}},  colours = {G.C.UI.TEXT_LIGHT}, shadow = true, float = true, scale = text_scale})}},
   }}
end

function FN.PRE.find_hand_text_area(node)
   if node.config and node.config.id == "hand_text_area" then
      return node
   end
   if node.nodes then
      for _, child in ipairs(node.nodes) do
         local found = FN.PRE.find_hand_text_area(child, id)
         if found then return found end
      end
   end
   return nil
end

--[[function FN.PRE.get_dollars_node()
   local top_color = FN.PRE.get_dollar_colour(0)
   local bot_color = top_color
   if FN.PRE.data ~= nil then
      top_color = FN.PRE.get_dollar_colour(FN.PRE.data.dollars.max)
      bot_color = FN.PRE.get_dollar_colour(FN.PRE.data.dollars.min)
   else
   end
   return {n=G.UIT.C, config={id = "fn_pre_dollars", align = "cm"}, nodes={
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "fn_pre_dollars_top", func = "fn_pre_dollars_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.dollars, ref_value = "top"}}, colours = {top_color}, shadow = true, spacing = 2, bump = true, scale = 0.5})}}
       }},
       {n=G.UIT.R, config={minh = 0.05}, nodes={}},
       {n=G.UIT.R, config={align = "cm"}, nodes={
           {n=G.UIT.O, config={id = "fn_pre_dollars_bot", func = "fn_pre_dollars_UI_set", object = DynaText({string = {{ref_table = FN.PRE.text.dollars, ref_value = "bot"}}, colours = {bot_color}, shadow = true, spacing = 2, bump = true, scale = 0.5})}},
       }}
   }}
end--]]

--
-- SETTINGS:
--

function FN.get_preview_settings_page()
   -- Rerun the sim so the change shows up right away
   local function prob_toggle_callback(_)
      if not G.HUD then return end

      FN.PRE.data = FN.PRE.simulate()
      FN.PRE.snapshot_pace()
      FN.PRE.update_prob_state()
      G.HUD:recalculate()
   end

   -- Same label width on every row, text on the left, checkboxes lined up on the right
   local function toggle(args)
      args.w = 4
      local t = create_toggle(args)
      t.nodes[1].config.align = "cl"
      return t
   end

   return
      {n=G.UIT.ROOT, config={align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes={
          toggle({id = "range_animation_toggle",
                  label = "Range Animation",
                  ref_table = G.SETTINGS.FN,
                  ref_value = "range_animation",
                  callback = prob_toggle_callback}),
          toggle({id = "prob_percentage_toggle",
                  label = "Probability Percentage",
                  ref_table = G.SETTINGS.FN,
                  ref_value = "prob_percentage",
                  callback = prob_toggle_callback})
      }}
end
