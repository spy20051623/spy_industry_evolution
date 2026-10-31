local core = ug_require("spy_industry_evolution::/growth_core.lua")
local M = {}
local cfg=core.config
function M.apply(result,levels)
  levels=levels or {}; local p=levels.production or 0; local b=levels.boost or 0
  local eco=1-core.environmentReduction(levels.environment)
  local logistics=levels.logistics or 0; local storage=levels.storage or 0; local jobs=levels.jobs or 0
  local loadingRate=cfg.loadingPerLevel
  result=core.copy(result)
  for _,sub in ipairs(result.subconstructions or {}) do
    local extra=core.extraOutput(p)
    for _,rule in ipairs(sub.rules or {}) do
      if rule.booster then
        if rule.boostFactor then rule.boostFactor=rule.boostFactor*(1+cfg.boostPerLevel*b) end
      elseif p>0 then
        -- Keep native inputs and increase each normal output at level milestones.
        rule.consumptionFactor=(rule.consumptionFactor or 1)*(1+cfg.throughputPerLevel*p)
        if extra>0 then for cargo,n in pairs(rule.output or {}) do
          if n>0 then rule.output[cargo]=n+extra end
        end end
      end
    end
    for _,stock in ipairs(sub.stocks or {}) do
      stock.capacity=math.floor(stock.capacity*(1+cfg.storagePerLevel*storage)+0.5)
      stock.loadSpeedModifier=(stock.loadSpeedModifier or 1)*(1+loadingRate*logistics)
    end
    if sub.personCapacity then
      sub.personCapacity.capacity=math.floor(sub.personCapacity.capacity*(1+cfg.jobsPerLevel*jobs)+0.5)
      if sub.personCapacity.destinationWeight then
        sub.personCapacity.destinationWeight=sub.personCapacity.destinationWeight*(1+cfg.jobDestinationWeightPerLevel*jobs)
      end
    end
    for _,lane in ipairs(sub.laneLists or {}) do
      local freight=false
      for _,mode in ipairs(lane.transportModes or {}) do if mode=="TRUCK" then freight=true end end
      if freight and lane.speedLimit and lane.speedLimit<cfg.speedLimit then
        lane.speedLimit=math.min(cfg.speedLimit,lane.speedLimit+cfg.speedPerLevel*logistics)
      end
    end
    if sub.station then
      for _,terminal in ipairs(sub.station.terminals or {}) do
        for _,speed in ipairs(terminal.cargoTransferSpeeds or {}) do
          -- Freight already receives the factor through its stock. Applying
          -- it here too multiplies the same upgrade twice. Passengers have
          -- no freight stock, so their dedicated terminal still receives it.
          local classes=speed.cargoTypeSet and speed.cargoTypeSet.cargoClassesIncluded or {}
          if #classes==1 and classes[1]=="PASSENGERS" then
            speed.loadSpeedModifier=(speed.loadSpeedModifier or 1)*(1+loadingRate*logistics)
          end
        end
      end
    end
    for _,emission in ipairs(sub.metadata and sub.metadata.emissions or {}) do
      if emission.noise then emission.noise=emission.noise*eco end
      if emission.pollution then emission.pollution=emission.pollution*eco end
    end
    if sub.emissionEmitter then
      sub.emissionEmitter.noisePower=(sub.emissionEmitter.noisePower or 0)*eco
      sub.emissionEmitter.pollutionPower=(sub.emissionEmitter.pollutionPower or 0)*eco
    end
  end
  for _,emission in ipairs(result.fieldConfig and result.fieldConfig.emissionConfig or {}) do
    emission.noise=(emission.noise or 0)*eco; emission.pollution=(emission.pollution or 0)*eco
  end
  return result
end
return M
