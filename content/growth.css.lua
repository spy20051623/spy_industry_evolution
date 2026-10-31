local ssu=require "::/gui/main/stylesheetutil.lua"
function data()
  local result={};local a=ssu.makeAdder(result)
  local colors=api.gui.genericRep.findAndGet("::/gui/main/default_colors.gres").data
  a("!spy-growth-root",{size={400,-1},gravity={-1,0}})
  a("!spy-growth-root TextView",{textAutoWrap=true,maxSize={400,-1}})
  a("!spy-growth-root !spy-growth-balance",{padding={4,8,8,8},gravity={-1,0}})
  a("!spy-growth-root !spy-growth-points-heading",{fontSize=16,fontWeight="Medium",margin={4,0,0,0}})
  a("!spy-growth-root !spy-growth-number",{fontSize=28,fontWeight="Medium",color=colors.AccentLight})
  a("!spy-growth-root !spy-growth-muted",{fontSize=14,color=colors.NeutralLight,margin={3,0,5,0}})
  a("!spy-growth-root !spy-growth-tab",{gravity={-1,0},minSize={0,36},padding={7,8,7,8},margin={6,2,8,2},
    backgroundImage1={fileName="::/gui/entity_window/design/card_surface.tga",horizontal={0,6,26,32},vertical={0,6,26,32}},
    borderImage={fileName="::/gui/entity_window/design/card_contour.tga",horizontal={0,6,26,32},vertical={0,6,26,32}},
    backgroundColor1=colors.BaseLight,borderColor=colors.NeutralMedium})
  a("!spy-growth-root !spy-growth-tab TextView",{color=colors.NeutralLightest,fontWeight="Medium"})
  a("!spy-growth-root !spy-growth-tab:hover",{backgroundColor1=colors.AccentVeryDark,borderColor=colors.AccentLight})
  a("!spy-growth-root !spy-growth-tab!spy-growth-selected",{backgroundColor1=colors.AccentDark,borderColor=colors.AccentLight})
  a("!spy-growth-root !spy-growth-tab!spy-growth-selected:hover",{backgroundColor1=colors.AccentDark,borderColor=colors.AccentLight})
  a("!spy-growth-root !spy-growth-route",{padding={8,0,8,0},gravity={-1,0}})
  a("!spy-growth-root !spy-growth-route-name",{fontSize=17,fontWeight="Medium"})
  a("!spy-growth-root !spy-growth-icon",{size={22,22},margin={0,8,0,0},color=colors.AccentLight})
  a("!spy-growth-root !spy-growth-level",{minSize={40,-1},margin={0,5,0,4},color=colors.NeutralLight})
  a("!spy-growth-root !spy-growth-cost",{fontSize=14,minSize={58,-1},margin={0,8,0,4},color=colors.NeutralLight})
  a("!spy-growth-root !spy-growth-upgrade",{minSize={64,28},padding={4,8,4,8}})
  a("!spy-growth-root !spy-growth-effect-name",{fontSize=14,margin={6,0,0,0}})
  a("!spy-growth-root !spy-growth-current",{fontSize=14,minSize={80,-1},margin={6,0,0,0}})
  a("!spy-growth-root !spy-growth-change, !spy-growth-root !spy-growth-change-label",{fontSize=14,minSize={80,-1},margin={6,0,0,0}})
  a("!spy-growth-root !spy-growth-next, !spy-growth-root !spy-growth-next-label",{fontSize=14,minSize={84,-1},margin={6,0,0,0}})
  a("!spy-growth-root !spy-growth-change",{color=colors.AccentLight})
  a("!spy-growth-root !spy-growth-next",{color=colors.AccentLight})
  a("!spy-growth-root !spy-growth-unavailable !spy-growth-icon",{color=colors.NeutralMedium})
  a("!spy-growth-root !spy-growth-reset",{minSize={64,32},padding={5,10,5,10},margin={0,0,0,6},gravity={1,0.5},
    backgroundImage1={fileName="::/gui/entity_window/design/card_surface.tga",horizontal={0,6,26,32},vertical={0,6,26,32}},
    borderImage={fileName="::/gui/entity_window/design/card_contour.tga",horizontal={0,6,26,32},vertical={0,6,26,32}},
    backgroundColor1=colors.AccentVeryDark,borderColor=colors.AccentVeryDark})
  a("!spy-growth-root !spy-growth-reset TextView",{color=colors.NeutralLightest,fontWeight="Medium"})
  a("!spy-growth-root !spy-growth-reset:hover",{backgroundColor1=colors.AccentDark,borderColor=colors.AccentLight})
  a("!spy-growth-root !spy-growth-reset:disabled",{backgroundColor1=colors.BaseLight,borderColor=colors.BaseLight})
  a("!spy-growth-root !spy-growth-reset:disabled TextView",{color=colors.NeutralMedium})
  a("!spy-growth-root !spy-growth-order",{padding={10,8,10,8},margin={4,0,4,0},gravity={-1,0},
    backgroundImage1={fileName="::/gui/entity_window/design/card_surface.tga",horizontal={0,6,26,32},vertical={0,6,26,32}},
    backgroundColor1=colors.BaseDark})
  a("!spy-growth-root !spy-growth-order Button",{gravity={-1,0},margin={5,0,0,0},padding={6,8,6,8}})
  a("!spy-growth-root !spy-growth-reward",{color=colors.AccentLight})
  a("!spy-growth-root !spy-growth-order-entry",{gravity={-1,0},padding={0,0,0,0},margin={4,0,4,0}})
  a("!spy-growth-root !spy-growth-order-entry:hover",{borderColor=colors.AccentLight})
  a("!spy-growth-root !spy-growth-task-goal",{fontSize=16,textAutoWrap=true,size={384,-1},maxSize={384,-1},margin={6,0,0,0}})
  a("!spy-growth-root !spy-growth-task-hint",{fontSize=14,color=colors.AccentLight,margin={8,8,5,8}})
  a("!spy-growth-root !spy-growth-task-tier",{fontSize=16,fontWeight="Medium"})
  a("!spy-growth-root !spy-growth-task-cost",{fontSize=15,color=colors.Negative,margin={0,10,0,0},gravity={1,0.5}})
  a("!spy-growth-root !spy-growth-task-reward",{fontSize=15,color=colors.AccentLight,gravity={1,0.5}})
  -- Applicable rules from Urban Games' entity_window.css.lua, in native order.
  -- Only recipe names change: preserve selector specificity and the cascade.
  -- Shared icon/font/hud classes continue to use the game's original styles.
  local gameplay=api.gui.genericRep.findAndGet("::/gui/entity_window/gameplay_colors.gres").data
  a("R::EntityWindowContent R::SpyGrowthWorkerIndicator",{size={-1,-1}})
  a("R::EntityWindowContent R::SpyGrowthWorkerIndicator BoxLayout",{
    innerSpacing={15,0},outerSpacing={1,0}})
  a("!booster-widget R::SpyGrowthWorkerProgressDisplay ProgressBar!extra-progress",{
    color=colors.NeutralVeryLight,backgroundColor1=colors.BaseLight})
  a("!booster-widget !boosted R::SpyGrowthWorkerProgressDisplay ProgressBar",{
    color=gameplay.IndustryBoost,backgroundColor1=colors.BaseLight})
  a("!booster-widget R::SpyGrowthWorkerProgressDisplay",{size={-1,-1},padding={0,8,0,0}})
  a("!boosted R::SpyGrowthWorkplacesBoosterProgressBar R::SpyGrowthWorkerProgressDisplay ProgressBar",{
    color=gameplay.IndustryBoost,backgroundColor1=colors.BaseLight})
  a("R::SpyGrowthWorkplacesBoosterProgressBar R::SpyGrowthWorkerProgressDisplay ProgressBar",{
    color=colors.NeutralVeryLight,backgroundColor1=colors.Invisible})
  a("R::EntityWindowContent R::SpyGrowthWorkerProgressDisplay ProgressBar",{
    gravity={-1,0.5},size={-1,25}})
  a("R::EntityWindowContent R::SpyGrowthWorkerProgressDisplay ProgressBar!extra-progress",{
    backgroundColor1=colors.BaseVeryLight})
  a("R::EntityWindowContent R::SpyGrowthWorkerProgressDisplay ProgressBar",{
    margin={2,2,2,2},gravity={-1,0.5},color=colors.AccentLight,backgroundColor1=colors.Invisible})
  return result
end
