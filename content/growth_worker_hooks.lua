local workers=ug_require("::/industries/industry_productivity_util.tl")
local M={}
local core=ug_require("spy_industry_evolution::/growth_core.lua")
local function parameters(e)
  if not api.engine.entityExists(e) then return nil end
  local ind=api.engine.getComponent(e,api.type.ComponentType.INDUSTRY)
  if not ind then return nil end
  local con=api.engine.getComponent(ind.construction,api.type.ComponentType.CONSTRUCTION)
  if not con then return nil end
  return con.params_native and con.params_native:asTable() or con.params
end
function M.install()
  if workers.spyGrowthInstalled then return end
  workers.spyGrowthInstalled=true
  local boosted=workers.isIndustryWorkersBoosted
  workers.isIndustryWorkersBoosted=function(e,n)
    local par=parameters(e)
    if par and par.spy_growth_jobs_base then
      n=n or #workers.getVisitors(e)
      return n>0 and n>=par.spy_growth_jobs_base*workers.RequiredWorkersFractionForBoost
    end
    return boosted(e,n)
  end
  local potential=workers.getPersonCapacityPotentialBoost
  workers.getPersonCapacityPotentialBoost=function(e)
    local base=potential(e);local par=parameters(e);local levels=par and par.spy_growth_levels
    return 1+(base-1)*(1+core.config.boostPerLevel*(levels and levels.boost or 0))
  end
end
function M.installProgress()
  local industry=ug_require("::/gui/main/industry_util.tl")
  if industry.spyGrowthProgressInstalled then return end
  industry.spyGrowthProgressInstalled=true
  local original=industry.getPersonCapacityBoostProgress
  industry.getPersonCapacityBoostProgress=function(e)
    local par=parameters(e)
    if par and par.spy_growth_jobs_base and par.spy_growth_jobs_base>0 then
      return math.min(1,#workers.getVisitors(e)/(par.spy_growth_jobs_base*workers.RequiredWorkersFractionForBoost))
    end
    return original(e)
  end
end
return M
