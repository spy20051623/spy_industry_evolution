local util=ug_require("::/scripts/util.tl")
local effects=ug_require("spy_industry_evolution::/growth_effects.lua")
function data()
  return {update=function(capture,params)
    local original=util.useFn(capture.spy_growth_original)
    local result=original(capture,params)
    if params.spy_growth_levels then return effects.apply(result,params.spy_growth_levels) end
    return result
  end}
end
