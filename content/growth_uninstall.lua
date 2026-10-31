-- Construction cleanup shared by the engine and its offline tests.
local M={}

function M.isTagged(params)
  for key in pairs(params or {}) do
    if type(key)=="string" and key:sub(1,11)=="spy_growth_" then return true end
  end
  return false
end

function M.hasEffects(params)
  for key in pairs(params or {}) do
    if type(key)=="string" and key:sub(1,11)=="spy_growth_" and key~="spy_growth_id" then return true end
  end
  return false
end

function M.cleanParams(params)
  local result={}
  for key,value in pairs(params or {}) do
    if type(key)~="string" or key:sub(1,11)~="spy_growth_" then result[key]=value end
  end
  return result
end

function M.isBonusStock(stock,base)
  local tag=stock and stock.tag
  return type(tag)=="number" and tag>base and tag<base+1000000
end

return M
