--- Original: Divvy's Preview for Balatro - Init.lua
--
-- Global values that must be present for the rest of this mod to work.

if not FN then FN = {} end

FN.PRE = {
   data = {
      score = {min = 0, exact = 0, max = 0},
      dollars = {min = 0, exact = 0, max = 0}
   },
   text = {
      score = {l = "", r = "", dash = "", pct = ""},
      dollars = {top = "", bot = ""},
      button = {label = ""},
   },
   joker_order = {},
   hand_order = {},
   show_preview = false,
   auto_calculate = true,
   on_startup = true,
}



FN.PRE._start_up = Game.start_up
function Game:start_up()
   FN.PRE._start_up(self)

   if not G.SETTINGS.FN then G.SETTINGS.FN = {} end
   if not G.SETTINGS.FN.PRE then
      G.SETTINGS.FN.PRE = true

      G.SETTINGS.FN.show_min_max = true

      -- On by default. With both off the sweep and (NN%) are skipped entirely (see sim_func)
      G.SETTINGS.FN.range_animation = true
      G.SETTINGS.FN.prob_percentage = true
   end

   -- Older saves already have FN.PRE set, so default these here too (nil would read as off)
   G.SETTINGS.FN.prob_animation = nil -- old name for range_animation
   if G.SETTINGS.FN.range_animation == nil then G.SETTINGS.FN.range_animation = true end
   if G.SETTINGS.FN.prob_percentage == nil then G.SETTINGS.FN.prob_percentage = true end
end
