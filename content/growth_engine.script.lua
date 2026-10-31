local core=ug_require("spy_industry_evolution::/growth_core.lua")
local uninstall=ug_require("spy_industry_evolution::/growth_uninstall.lua")
local workers=ug_require("::/industries/industry_productivity_util.tl")
local entityUtil=ug_require("::/scripts/entity_util.tl")
local CT=api.type.ComponentType
local PREFIX="spy_industry_evolution"
local PRODUCTION_VERSION=7
local BALANCE_VERSION=1
local MIGRATION_STRATEGY_VERSION=2
local taskNotificationType=PREFIX.."::/growth_task_notification.script"
local function component(e,t)
  if not e or e<0 or not api.engine.entityExists(e) then return nil end
  return api.engine.getComponent(e,t)
end
local function constructionFor(e)
  local ind=component(e,CT.INDUSTRY)
  if not ind then return nil end
  return ind.construction,component(ind.construction,CT.CONSTRUCTION),ind
end
local function paramsOf(con)
  if con.params_native then return con.params_native:asTable() end
  return core.copy(con.params)
end
ug_require("spy_industry_evolution::/growth_worker_hooks.lua").install()
local function roadTransport(con)
  local groups=api.engine.system.stationGroupSystem
  local known=false
  if groups then for _,station in ipairs(con.stations or {})do
    local group=groups.getStationGroup(station)
    local sg=component(group,CT.STATION_GROUP)
    for index,e in ipairs(sg and sg.stations or {})do if e==station then
      -- The API returns {carriers, transportModes}, not a flat carrier list.
      local transport=groups.getCarriers(group,index-1,-1)
      local carriers=transport and transport[1]
      for _,carrier in ipairs(carriers or {})do
        known=true;if carrier==api.type["enum"].Carrier.ROAD then return true end
      end
    end end
  end end
  if known then return false end
  local rep=api.res.constructionRep
  if rep then
    local id=rep.find(con.fileName)
    if id and id>=0 then local def=rep.get(id)
      return core.hasRoadTransport(def.updateScript and def.updateScript.params)
    end
  end
end
local function inspect(e)
  local ce,con,ind=constructionFor(e); if not con then return nil end
  local stock=component(ind.stockList,CT.STOCK_LIST); if not stock then return nil end
  local input,output,normalInput,boostInput={},{},{},{}
  for _,rule in ipairs(stock.rules) do
    for _,opt in ipairs(rule.input) do for idx,n in pairs(opt) do
      if n>0 and stock.stocks[idx] then
        local cargo=stock.stocks[idx].cargoType;input[cargo]=true
        local eligible=rule.booster and boostInput or normalInput;eligible[cargo]=true
      end
    end end
    if not rule.booster then for cargo,n in pairs(rule.output) do if n>0 then output[cargo]=true end end end
  end
  local pc=component(e,CT.PERSON_CAPACITY)
  local par=paramsOf(con); local old=par.spy_growth_levels or {}
  -- Existing constructions store their original capacity. Do not derive it
  -- using the new balance factor when loading an older upgraded save.
  local previousRate=par.spy_growth_jobs_version==2 and core.config.jobsPerLevel or 0.2
  local baseJobs=par.spy_growth_jobs_base or
    (pc and math.floor(pc.capacity/(1+previousRate*(old.jobs or 0))+0.5) or 0)
  local hasProduction=next(output)~=nil
  return {entity=e,construction=ce,con=con,params=par,input=input,normalInput=normalInput,boostInput=boostInput,output=output,stock=ind.stockList,
    jobs=baseJobs,hasRoadTransport=roadTransport(con),available={supply=next(normalInput)~=nil,boost=next(boostInput)~=nil,products=hasProduction,workers=baseJobs>0},
    supported={production=hasProduction,boost=hasProduction and baseJobs>0,environment=component(e,CT.EMISSION_EMITTER)~=nil,
      logistics=#con.stations>0,storage=#stock.stocks>0,jobs=baseJobs>0}}
end
local function refresh(f,info)
  local risk=api.res.getBaseConfig().advancedOptions.subventionRisk
  core.generate(f,info.available,risk,math.ceil(info.jobs*workers.RequiredWorkersFractionForBoost),math.random)
end
local function factory(s,e)
  -- Vanilla cargo subsidies point at the stock-list entity; worker subsidies
  -- point at the industry itself. Resolve both to the same industry first.
  if not component(e,CT.INDUSTRY) then
    local stockListEntity=e
    e=nil
    api.engine.forEachEntityWithComponent(function(candidate)
      local industry=component(candidate,CT.INDUSTRY)
      if industry and industry.stockList==stockListEntity then e=candidate end
    end,CT.INDUSTRY)
  end
  local info=inspect(e); if not info then return nil,nil end
  local id=info.params.spy_growth_id
  local f=id and s.factories[id]
  if not f then for _,v in pairs(s.factories) do if v.construction==info.construction then f=v; break end end end
  if not f then
    id=tostring(s.nextId); s.nextId=s.nextId+1; f=core.newFactory(id); s.factories[id]=f
    f.entity=e; f.construction=info.construction; f.supported=info.supported; f.pending=info.pending; refresh(f,info)
  end
  f.entity=e; f.construction=info.construction; f.supported=info.supported; f.pending=info.pending;f.hasRoadTransport=info.hasRoadTransport
  core.retargetOffers(f,not info.available.supply and info.available.boost)
  return f,info
end
local function errorText(f,key)
  f.error=key;f.errorVersion=(f.errorVersion or 0)+1;f.revision=f.revision+1
end
local function constructionMatches(e,levels)
  local _,con=constructionFor(e)
  if not con then return false end
  local actual=paramsOf(con).spy_growth_levels or {}
  for _,route in ipairs(core.routes) do
    if (actual[route.key] or 0)~=(levels[route.key] or 0) then return false end
  end
  return true
end
local function currentTaskCargoTypes(task,info)
  local types=task.kind=="boost" and info.boostInput or task.kind=="supply" and
    (task.factor and info.normalInput or info.input) or task.kind=="products" and info.output or {}
  local result={};for cargo in pairs(types)do result[#result+1]=cargo end
  table.sort(result)
  return result
end
local function notificationTask(f,info,completed)
  local task=completed and f.lastCompletedTask or f.task
  if not task then return end
  if not task.uid then f.nextTaskId=(f.nextTaskId or 0)+1;task.uid=f.id..":"..f.nextTaskId end
  task=core.copy(task)
  task.cargoTypes=currentTaskCargoTypes(task,info)
  return task
end
local function notifyCompletedTask(f,info)
  local task=notificationTask(f,info,true)
  if not task then return end
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("","Notifications","add",{
    type=taskNotificationType,
    params={factoryId=f.id,entity=f.entity,task=task,completed=true,
      name=api.engine.util.getEntityName and api.engine.util.getEntityName(f.entity)},
    autoDismissDuration=core.config.taskNotificationDurationMs}))
end
local function syncTaskNotifications(s)
  local entries={}
  local scriptEntity=api.engine.system.gameScriptSystem.getEntityForGameScript(PREFIX.."::/growth.gs")
  if scriptEntity and scriptEntity>=0 then
    local anchor=entityUtil.makeEntityAndRevision0Array({scriptEntity})
    local ids={};for id in pairs(s.factories)do ids[#ids+1]=id end
    table.sort(ids)
    if not s.uninstall then for _,id in ipairs(ids)do
      local f=s.factories[id]
      if f.task then
        local info=inspect(f.entity)
        if info then
          local task=notificationTask(f,info,false)
          -- Progress is read live by the notification recipe. Keep these
          -- parameters stable so a manually dismissed message stays hidden.
          task.progress=0
          entries[#entries+1]={entities=anchor,
            param={factoryId=f.id,entity=0,task=task,completed=false}}
        end
      end
    end end
  end
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("","Notifications","updatePersistent",{
    type=taskNotificationType,entitiesAndParam=entries,passOnlyParam=true}))
end
local function charge(n,position)
  local entry=api.type.JournalEntry.new(); entry.amount=-n; entry.time=-1
  entry.category.type=api.type.JournalEntry.Type.SUBSIDY
  api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(),entry,position or api.type.Vec3f.new(0,0,0)))
end
-- Vanilla finance uses nil for infinite money (the no-costs game mode).
local function balance() return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer()) or math.huge end
local function subsidyState()
  local e=api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/subventions/subventions.gs")
  local c=component(e,CT.GAME_SCRIPT); if not c then return nil end
  return c.state_native and c.state_native:asTable() or c.state
end
local factorySubsidies=core.factorySubsidies
local townSubsidies=core.townSubsidies
local subsidyKey=core.subsidyKey
local targetOf=core.subsidyTarget
local function seedSubsidies(s)
  local existing=subsidyState(); if not existing then return false end
  for _,list in ipairs({"proposedSubventions","activeSubventions","completedSubventions","failedSubventions"}) do
    for _,t in pairs(existing[list] or {}) do s.subsidySeen[subsidyKey(t)]="old" end
  end
  s.initialized=true; return true
end
local function pollSubsidies(s)
  local existing=subsidyState(); if not existing then return end
  for _,list in ipairs({"proposedSubventions","activeSubventions","completedSubventions","failedSubventions"}) do
    for _,t in pairs(existing[list] or {}) do
      if factorySubsidies[t.id] or townSubsidies[t.id] then
        local key=subsidyKey(t); local mark=s.subsidySeen[key]
        if mark==nil then mark="new"; s.subsidySeen[key]=mark end
        if list=="completedSubventions" and mark=="new" then
          if factorySubsidies[t.id] then
            local f=factory(s,targetOf(t)); if f then core.award(s,f,core.subsidyReward) end
          else
            s.overflow=s.overflow+core.townSubsidyReward
          end
          s.subsidySeen[key]="paid"
        end
      end
    end
  end
end
local function syncWorkerBoost(e)
  local _,con,ind=constructionFor(e)
  if not con or not paramsOf(con).spy_growth_levels then return end
  local stock=component(ind.stockList,CT.STOCK_LIST)
  if not stock or not component(e,CT.PERSON_CAPACITY) then return end
  local value=workers.isIndustryWorkersBoosted(e) and workers.getPersonCapacityPotentialBoost(e) or 1
  if math.abs(stock.modifiers.productivity-value)>0.000001 then
    local modifiers=api.type.StockList.Modifiers.new(stock.modifiers)
    modifiers.productivity=value
    api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(e,modifiers))
  end
end
local function replaceConstruction(state,s,construction,params,onStart,onResult,ignoreErrors)
  local prepared,command=pcall(function()
    local proposal=api.engine.util.proposal.createProposalReplaceConstruction(construction,params)
    return proposal and api.cmd.makeWorldBuildProposalCmd(proposal,nil,ignoreErrors or false,false,false)
  end)
  if not prepared or not command then return false end
  onStart()
  state:set(s)
  local completed=false
  local function finish(success)
    if completed then return end
    completed=true
    local latest=state:get()
    onResult(latest,success)
    state:set(latest)
  end
  -- Keep callback errors outside pcall, including synchronous test/engine callbacks.
  local sending=true
  local immediate
  local sent=pcall(api.cmd.sendCommand,command,function(_,success)
    if completed or immediate then return end
    if sending then immediate={success=success} else finish(success) end
  end)
  sending=false
  if immediate then finish(immediate.success) elseif not sent then finish(false) end
  return true
end
local function upgradedParams(params,id,levels,jobs)
  local par=core.copy(params)
  par.spy_growth_id=id;par.spy_growth_levels=core.copy(levels)
  par.spy_growth_jobs_base=jobs
  par.spy_growth_production_version=PRODUCTION_VERSION
  par.spy_growth_balance_version=BALANCE_VERSION
  par.spy_growth_environment_version=5
  par.spy_growth_logistics_version=3
  par.spy_growth_jobs_version=2
  par.spy_growth_bonus_stocks=false
  return par
end
local function refundUpgrades(s,f)
  local target=f.upgradeTarget
  if target then
    f.points=f.points+target.own
    s.overflow=s.overflow+target.global
  end
  f.upgradeTarget=nil;f.upgradeBatch=nil
  f.upgradeStepQueued=nil;f.upgradeStepQueuedAt=nil
end
local function failUpgrade(f,details)
  details.version=(f.upgradeFailure and f.upgradeFailure.version or 0)+1
  f.upgradeFailure=details
end
local function failMigration(s,f)
  if f.upgradeTarget then
    refundUpgrades(s,f)
    failUpgrade(f,{reason="migration",restored=constructionMatches(f.entity,f.levels),batch=true})
  else
    if f.error~="growth_migration_failed" then errorText(f,"growth_migration_failed") end
  end
end
local function rebuild(state,s,f,info,working,cost,newOverflow,upgrade,migration,refreshOnly)
  local par=upgradedParams(info.params,f.id,working.levels,info.jobs)
  local overflowChange=newOverflow-s.overflow
  local queued=replaceConstruction(state,s,info.construction,par,function()
    f.busy=true
    if upgrade then f.upgradeBatch=core.copy(upgrade) end
  end,function(latest,success)
    local original=latest.factories[f.id]
    if not original then return end
    if success then
      if refreshOnly then
        -- A free parameter refresh does not change the ledger. Keep rewards
        -- and worker visits received while the construction command ran.
        working=core.copy(original)
      elseif upgrade or migration then
        local levels=working.levels
        working=core.copy(original)
        working.levels=levels
        if upgrade then
          core.commitUpgrade(working,upgrade)
        end
        working.upgradeStepQueued=nil;working.upgradeStepQueuedAt=nil
        -- Preserve later reservations, rewards, tasks and worker visits.
        working.revision=original.revision+1
      end
      if migration then
        working.migrationBuildAttempted=true
        working.migrationTrimKey=nil;working.migrationTrimCount=nil
        working.migrationClearVersion=nil
      end
      working.busy=false; working.needsRelink=true; working.error=nil; latest.factories[f.id]=working
      latest.overflow=(latest.overflow or 0)+overflowChange
      if upgrade then core.sweep(latest,working) end
      if cost>0 then charge(cost) end
    else
      original.busy=false
      if upgrade then
        if migration then original.migrationBuildFailed=true end
        refundUpgrades(latest,original)
        failUpgrade(original,{reason=migration and "migration" or "build",batch=true,
          restored=constructionMatches(original.entity,original.levels)})
      elseif migration then
        original.migrationBuildFailed=true
        failMigration(latest,original)
      else errorText(original,"growth_apply_failed") end
    end
  end,migration)
  if not queued then
    if upgrade then
      if migration then f.migrationBuildFailed=true end
      refundUpgrades(s,f)
      failUpgrade(f,{reason="proposal",restored=true,batch=true})
    elseif migration then f.migrationBuildFailed=true;failMigration(s,f)
    else errorText(f,"growth_apply_failed") end
  end
  return queued
end
local function bonusStock(v)
  return uninstall.isBonusStock(v,core.config.bonusStockTagBase)
end
local function needsProductionMigration(f,par,stock)
  if ((f.levels.production or 0)>0 or par.spy_growth_bonus_stocks) and
      par.spy_growth_production_version~=PRODUCTION_VERSION then return true end
  -- A previous rebuild may have written the current version marker while the
  -- native stock list still retained legacy output slots. Inspect the slots.
  for _,v in ipairs(stock and stock.stocks or {}) do
    if bonusStock(v) then return true end
  end
  return false
end
local function needsBalanceUpdate(f,par)
  if par.spy_growth_balance_version==BALANCE_VERSION then return false end
  -- Queued upgrades also apply the latest parameters; do not rebuild ahead
  -- of them or overwrite point reservations made by later clicks.
  if f.upgradeTarget then return false end
  return (f.levels.production or 0)>0 or (f.levels.boost or 0)>0 or (f.levels.logistics or 0)>0
end
-- Return one stock that cannot survive the requested construction capacity.
-- The caller issues one command at a time and re-reads the live stock list.
local function excessStock(ind,storageLevel,technicalOutput)
  local stock=ind and component(ind.stockList,CT.STOCK_LIST)
  if not stock then return nil,false end
  local factor=1+core.config.storagePerLevel*(storageLevel or 0)
  local reserved={}
  if technicalOutput then
    for _,v in ipairs(stock.stocks or {}) do
      if bonusStock(v) then reserved[v.cargoType]=(reserved[v.cargoType] or 0)+(v.capacity or 0) end
    end
  end
  for i,v in ipairs(stock.stocks or {})do
    local count=api.engine.system.simEntityAtStockSystem.getStockCount(ind.stockList,i-1)
    local capacity=v.capacity or 0
    if not bonusStock(v) and v.type==api.type["enum"].StockListType.OutputStock and reserved[v.cargoType] then
      capacity=capacity+reserved[v.cargoType]
      reserved[v.cargoType]=nil
    end
    -- Deleted technical stocks and their cargo are handled by the construction
    -- replacement itself; they must never block reset or disable.
    if not bonusStock(v) then
      local target=math.floor(capacity/factor+0.5)
      if count>target then return {stockList=ind.stockList,index=i-1,target=target,count=count},true end
    end
  end
  return nil,true
end
-- Shared reset/disable stock cleanup. The caller owns its busy flag and what
-- happens after the command; this helper owns the retry guard and stock write.
local function clearForVanilla(state,s,ind,storageLevel,technicalOutput,progress,keyPrefix,onStart,onResult)
  local trim,available=excessStock(ind,storageLevel,technicalOutput)
  if not available then return "unavailable" end
  if not trim then progress.trimKey=nil;progress.trimCount=nil;return "ready" end
  local key=tostring(keyPrefix)..":"..tostring(trim.index)
  if progress.trimKey==key and trim.count>=(progress.trimCount or 0) then return "stalled" end
  -- Some game builds may not expose this command. Check and construct it
  -- before recording a busy operation that would otherwise have no callback.
  local makeCommand=api.cmd.debug and api.cmd.debug.makeStockSetCargoAmountCmd
  if type(makeCommand)~="function" or type(api.cmd.sendCommand)~="function" then return "unavailable" end
  local made,command=pcall(makeCommand,trim.stockList,trim.index,trim.target)
  if not made or not command then return "unavailable" end
  progress.trimKey=key;progress.trimCount=trim.count
  onStart()
  state:set(s)
  local completed=false
  local function finish(success)
    if completed then return end
    completed=true
    onResult(state:get(),success)
  end
  -- Keep result handling outside the protected send, including when a command
  -- completes synchronously. A callback error is not a command-dispatch error.
  local sending=true
  local immediate
  local sent=pcall(api.cmd.sendCommand,command,function(_,success)
    if completed or immediate then return end
    if sending then immediate={success=success} else finish(success) end
  end)
  sending=false
  if immediate then finish(immediate.success)
  elseif not sent then finish(false) end
  return "pending"
end
local function startUpgrade(state,s,f)
  if f.busy or f.needsRelink or not f.upgradeTarget then return end
  local info=inspect(f.entity)
  if not info then
    refundUpgrades(s,f)
    failUpgrade(f,{reason="factory",restored=false,batch=true})
    return
  end
  local migration=needsProductionMigration(f,info.params,component(info.stock,CT.STOCK_LIST))
  if migration and f.migrationBuildFailed then failMigration(s,f);return end
  -- Freeze only the submitted proposal. Later clicks keep updating the target.
  local batch=core.copy(f.upgradeTarget)
  for _,route in ipairs(core.routes) do
    local level=batch.levels[route.key] or 0
    if level>(f.levels[route.key] or 0) and (not info.supported[route.key] or level>route.max) then
      refundUpgrades(s,f)
      failUpgrade(f,{reason=level>route.max and "max" or "unsupported",
        restored=constructionMatches(f.entity,f.levels),batch=true})
      return
    end
  end
  local work=core.copy(f);work.levels=core.copy(batch.levels)
  return rebuild(state,s,f,info,work,0,s.overflow,batch,migration)
end
local function action(state,s,p)
  if s.uninstall or s.suspendRequested and p.action~="upgrade_step" and
    p.action~="upgrade_failure_seen" then return end
  if p.action=="upgrade" then
    local f=p.factoryId and s.factories[p.factoryId]
    if not f then f=factory(s,p.entity) end
    if not f then return end
    if f.busy and not f.upgradeTarget then return end
    local ticket=tonumber(p.ticket)
    if not ticket or ticket<=(f.upgradeTicket or 0) then return end
    f.upgradeTicket=ticket
    if (p.failureEpoch or 0)~=(f.upgradeFailure and f.upgradeFailure.version or 0) then return end
    local target=f.upgradeTarget or {levels=core.copy(f.levels),own=0,global=0}
    local work={levels=target.levels,points=f.points,supported=f.supported}
    local paid,err=core.payment(s,work,p.route)
    if not paid then
      failUpgrade(f,{ticket=ticket,route=p.route,
        level=(work.levels[p.route] or 0)+1,reason=err or "state",
        restored=constructionMatches(f.entity,f.levels)})
      return
    end
    f.error=nil
    f.points=f.points-paid.own;s.overflow=s.overflow-paid.global
    target.levels[p.route]=(target.levels[p.route] or 0)+1
    target.own=target.own+paid.own;target.global=target.global+paid.global
    f.upgradeTarget=target
    return
  end
  if p.action=="upgrade_step" then
    local f=s.factories[p.factoryId]
    if f then
      f.upgradeStepQueued=nil;f.upgradeStepQueuedAt=nil
      if startUpgrade(state,s,f) then return true end
    end
    return
  end
  if p.action=="upgrade_failure_seen" then
    local f=s.factories[p.factoryId]
    if f and f.upgradeFailure and f.upgradeFailure.version==p.version then
      f.upgradeFailure.seen=true
    end
    return
  end
  local f,info=factory(s,p.entity); if not f then return end
  if p.action=="open" then
    if f.upgradeTarget then return end
    local needsProductionUpdate=needsProductionMigration(f,info.params,component(info.stock,CT.STOCK_LIST))
    local needsUpdate=needsProductionUpdate or needsBalanceUpdate(f,info.params) or
      ((f.levels.environment or 0)>0 and info.params.spy_growth_environment_version~=5) or
      ((f.levels.logistics or 0)>0 and info.params.spy_growth_logistics_version~=3) or
      ((f.levels.jobs or 0)>0 and info.params.spy_growth_jobs_version~=2)
    if needsUpdate and not f.busy then
      if needsProductionUpdate then
        if f.migrationBuildFailed or f.migrationBuildAttempted then
          f.migrationBuildFailed=true
          failMigration(s,f)
          return
        end
        -- The old tagged stocks are deleted with the construction. Their
        -- contents are intentionally not copied into the new output stocks.
        return rebuild(state,s,f,info,core.copy(f),0,s.overflow,nil,true)
      end
      return rebuild(state,s,f,info,core.copy(f),0,s.overflow,nil,nil,true)
    end
    return
  end
  if f.busy or f.upgradeTarget then return end
  if p.revision~=f.revision then errorText(f,"growth_stale"); return end
  f.error=nil
  if p.action=="accept" then
    local c=f.candidates[p.tier]; if f.task or not c then return end
    if balance()<c.cost then errorText(f,"growth_money_needed"); return end
    local cost=c.cost; core.accept(f,p.tier); charge(cost); syncTaskNotifications(s)
  elseif p.action=="cancel" then
    if f.task then f.task=nil; f.seenCargo={}; refresh(f,info); syncTaskNotifications(s) end
  elseif p.action=="reset" then
    local trial=core.copy(s); local work=trial.factories[f.id]; local cost=0
      if core.spent(f)==0 then return end
      cost=core.resetCost(f)
      if balance()<cost then errorText(f,"growth_money_needed"); return end
      core.reset(trial,work)
      local status=clearForVanilla(state,s,component(info.entity,CT.INDUSTRY),
        (info.params.spy_growth_levels or {}).storage,
        (info.params.spy_growth_production_version or 0)>=3 and (f.levels.production or 0)>0,
        f,info.stock,function()
          f.busy=true
        end,function(latest,ok)
          local current=latest.factories[f.id]
          if not current then return end
          current.busy=false
          if not ok then
            current.trimKey=nil;current.trimCount=nil
            errorText(current,"growth_apply_failed")
          end
          state:set(latest)
          if ok then api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("",PREFIX,"reset",{entity=p.entity,revision=p.revision})) end
        end)
      if status=="pending" then return true end
      if status~="ready" then
        f.trimKey=nil;f.trimCount=nil;errorText(f,"growth_apply_failed");return
      end
    -- Do not commit either point deduction or financial charge on a failed build.
    return rebuild(state,s,f,info,work,cost,trial.overflow)
  end
end
-- Rebuild older constructions when production or other effect versions change.
local function productionTick(s,now)
  for _,f in pairs(s.factories)do
    if not f.busy and not f.needsRelink and not f.migrationBuildFailed and
      not f.upgradeTarget then
      local _,con,ind=constructionFor(f.entity)
      local stock=ind and component(ind.stockList,CT.STOCK_LIST)
      if stock then
        local par=paramsOf(con)
        if needsProductionMigration(f,par,stock) or needsBalanceUpdate(f,par) or
          ((f.levels.environment or 0)>0 and par.spy_growth_environment_version~=5) or
          ((f.levels.logistics or 0)>0 and par.spy_growth_logistics_version~=3) or
          ((f.levels.jobs or 0)>0 and par.spy_growth_jobs_version~=2) then
          if not f.productionMigrationAt or now-f.productionMigrationAt>5000 then
            f.productionMigrationAt=now
            api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("",PREFIX,"production_migrate",{entity=f.entity}))
          end
        end
      end
    end
  end
end

local function onCargo(s,list)
  for _,event in ipairs(list or {}) do
    local cargo=component(event.simEntity,CT.SIM_CARGO)
    local source=cargo and cargo.sourceEntity
    for _,f in pairs(s.factories) do
      if f.task and not f.busy then
        local info=inspect(f.entity)
        if info then
          local kind=f.task.kind; local valid=false
          if kind=="supply" or kind=="boost" then
            local accepted=kind=="boost" and info.boostInput or (f.task.factor and info.normalInput or info.input)
            valid=event.stockListEntity==info.stock and cargo and accepted[cargo.cargoType]
          elseif kind=="products" then valid=source==info.stock or source==f.entity; valid=valid and event.stockListEntity~=info.stock and cargo and info.output[cargo.cargoType] end
          if valid then
            local token=tostring(event.simEntity)..":"..tostring(cargo.startTime)
            if core.progress(s,f,kind,1,token) then
              f.lastCompletedTask.cargoTypes=currentTaskCargoTypes(f.lastCompletedTask,info)
              syncTaskNotifications(s);notifyCompletedTask(f,info);refresh(f,info)
            end
          end
        end
      end
    end
  end
end
local function onWorkers(s,p)
  local tracked={}
  local gameTime=component(api.engine.util.getWorld(),CT.GAME_TIME)
  for _,f in pairs(s.factories) do
    if (f.levels.jobs or 0)>0 and not f.needsRelink then tracked[f.entity]=f end
  end
  for _,e in ipairs(p.entities or {}) do
    local person=component(e,CT.SIM_PERSON)
    if person and person.lastMoveMode==api.type["enum"].MoveMode.LINES then
      local f=tracked[person.targetOrAtEntity]
      if f and gameTime then
        local pc=component(f.entity,CT.PERSON_CAPACITY)
        if pc and pc.capacity>0 then
          core.trackWorkerVisit(f,entityUtil.makeEntityAndRevision(e),gameTime.gameTime,pc.capacity,
            workers.workersTimeIntervalMax,not f.workerVisitors and workers.getVisitors(f.entity),entityUtil.entityEquals)
        end
      end
      for _,f in pairs(s.factories) do
        if f.task and not f.busy and f.task.kind=="workers" and person.targetOrAtEntity==f.entity then
          if core.progress(s,f,"workers",1) then local info=inspect(f.entity); if info then syncTaskNotifications(s);notifyCompletedTask(f,info);refresh(f,info) end end
        end
      end
    end
  end
end

-- Cleanup is global: old saves can have construction parameters even when the
-- game-script factory ledger has already been lost by a disabled save.
local function uninstallTick(state,s,now)
  local u=s.uninstall
  if not u or (u.status~="running" and u.status~="restoring") then return end
  if u.inFlight then
    if now-(u.startedAt or now)<30000 then return end
    -- A save/reload can lose a proposal callback. Rescan before retrying.
    u.inFlight=nil
  end
  if u.status=="restoring" then
    local suspended={}
    api.engine.forEachEntityWithComponent(function(e)
      local ce,con=constructionFor(e)
      local par=con and paramsOf(con)
      if par and par.spy_growth_id then suspended[par.spy_growth_id]={entity=e,construction=ce,params=par} end
    end,CT.INDUSTRY)
    local ids={}
    for id in pairs(s.factories)do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids)do
      local f=s.factories[id]
      local item=suspended[id]
      if not item then
        local ce,con=constructionFor(f.entity)
        if ce and ce==f.construction then item={entity=f.entity,construction=ce,params=paramsOf(con)} end
      end
      if not item then s.factories[id]=nil
      elseif not item.params.spy_growth_levels and (item.params.spy_growth_id or core.spent(f)>0) then
        local info=inspect(item.entity)
        if not info then u.status="blocked";u.reason="stock";u.blockedEntity=item.entity;return end
        local par=upgradedParams(item.params,id,f.levels,info.jobs)
        local queued=replaceConstruction(state,s,item.construction,par,function()
          u.inFlight=true;u.startedAt=now;u.blockedEntity=nil;u.reason=nil
        end,function(latest,success)
          local current=latest and latest.uninstall
          if not current or current.status~="restoring" then return end
          current.inFlight=nil;current.queuedAt=nil
          if success then current.cleaned=(current.cleaned or 0)+1
          else current.status="blocked";current.reason="proposal";current.blockedEntity=item.entity end
        end)
        if not queued then u.status="blocked";u.reason="proposal";u.blockedEntity=item.entity;return end
        return true
      else f.entity=item.entity;f.construction=item.construction;f.needsRelink=nil;f.busy=nil end
    end
    seedSubsidies(s)
    for _,f in pairs(s.factories)do
      local info=inspect(f.entity)
      if info then f.supported=info.supported;refresh(f,info);f.revision=f.revision+1 end
    end
    s.uninstall=nil
    return
  end
  local tagged={}
  api.engine.forEachEntityWithComponent(function(e)
    local ce,con,ind=constructionFor(e)
    local par=con and paramsOf(con)
    if par and (u.mode=="suspend" and uninstall.hasEffects(par) or u.mode~="suspend" and uninstall.isTagged(par)) then
      tagged[#tagged+1]={entity=e,construction=ce,params=par,industry=ind}
    end
  end,CT.INDUSTRY)
  table.sort(tagged,function(a,b)return a.entity<b.entity end)
  u.remaining=#tagged
  if #tagged==0 then
    u.status=u.mode=="suspend" and "disabled" or "ready";u.inFlight=nil;u.queuedAt=nil
    if u.mode~="suspend" then s.factories={};s.overflow=0 end
    return
  end
  -- Check pending builds and stock availability before modifying any factory.
  for _,item in ipairs(tagged)do
    local f=item.params.spy_growth_id and s.factories[item.params.spy_growth_id]
    if f and f.busy then
      u.status="blocked";u.reason="busy";u.blockedEntity=item.entity;return
    end
    if not item.industry or not component(item.industry.stockList,CT.STOCK_LIST) then
      u.status="blocked";u.reason="stock";u.blockedEntity=item.entity;return
    end
  end
  local item=tagged[1]
  local status=clearForVanilla(state,s,item.industry,
    (item.params.spy_growth_levels or {}).storage,
    (item.params.spy_growth_production_version or 0)>=3 and
      ((item.params.spy_growth_levels or {}).production or 0)>0,
    u,item.entity,function()
      u.inFlight=true;u.startedAt=now;u.blockedEntity=nil;u.reason=nil
    end,function(latest,success)
      local current=latest and latest.uninstall
      if not current or current.status~="running" then return end
      current.inFlight=nil;current.queuedAt=nil
      if success then
        if uninstallTick(state,latest,now) then return end
      else
        current.trimKey=nil;current.trimCount=nil
        current.status="blocked";current.reason="stock";current.blockedEntity=item.entity
      end
      state:set(latest)
    end)
  if status=="pending" then return true end
  if status~="ready" then
    u.status="blocked";u.reason="stock";u.blockedEntity=item.entity;return
  end
  local par=uninstall.cleanParams(item.params)
  if u.mode=="suspend" then par.spy_growth_id=item.params.spy_growth_id end
  local queued=replaceConstruction(state,s,item.construction,par,function()
    u.inFlight=true;u.startedAt=now;u.blockedEntity=nil;u.reason=nil
  end,function(latest,success)
    local current=latest and latest.uninstall
    if not current or current.status~="running" then return end
    current.inFlight=nil;current.queuedAt=nil
    if success then current.cleaned=(current.cleaned or 0)+1
    else current.status="blocked";current.reason="proposal";current.blockedEntity=item.entity end
  end)
  if not queued then u.status="blocked";u.reason="proposal";u.blockedEntity=item.entity;return end
  return true
end

local uninstallSessionInitialized=false
local notificationsInitialized=false
local function prepareUpgradeRecovery(s)
  local pending={}
  for id,f in pairs(s.factories) do
    f.upgradeStepQueued=nil;f.upgradeStepQueuedAt=nil
    if f.upgradeBatch and f.busy then pending[id]=true end
  end
  -- Script locals belong to separate engine worker contexts. Recovery must
  -- only claim batches present on load, never a new command from another VM.
  s.upgradeRecovery=next(pending) and {factories=pending} or nil
  s.upgradeRecoveryVersion=1
end
local function recoverUpgrades(s,pending)
  for id,f in pairs(s.factories) do
    local batch=f.upgradeBatch
    if pending[id] and batch and f.busy then
      local e=f.entity
      local ce,con=constructionFor(e)
      if not con then
        api.engine.forEachEntityWithComponent(function(candidate)
          local foundCe,foundCon=constructionFor(candidate)
          if foundCon and paramsOf(foundCon).spy_growth_id==id then
            e=candidate;ce=foundCe;con=foundCon
          end
        end,CT.INDUSTRY)
      end
      if con then
        f.entity=e;f.construction=ce
        local actual=paramsOf(con).spy_growth_levels or {}
        local expected=batch.levels
        local function matches(levels)
          for _,route in ipairs(core.routes) do
            if (actual[route.key] or 0)~=(levels[route.key] or 0) then return false end
          end
          return true
        end
        if matches(expected) then
          core.commitUpgrade(f,batch);f.revision=f.revision+1
          f.busy=false;f.needsRelink=nil
          core.sweep(s,f)
        elseif matches(f.levels) then
          f.busy=false;f.needsRelink=nil;f.upgradeBatch=nil
        else
          f.busy=false;refundUpgrades(s,f)
          failUpgrade(f,{reason="state",restored=false,batch=true})
        end
      else
        f.busy=false;refundUpgrades(s,f)
        failUpgrade(f,{reason="factory",restored=false,batch=true})
      end
    end
  end
end
local function beginSuspend(s)
  for _,f in pairs(s.factories)do
    if f.busy or f.upgradeTarget then return false end
  end
  for _,f in pairs(s.factories)do
    f.task=nil;f.candidates={};f.seenCargo={};f.productionReward=nil
    f.revision=f.revision+1
  end
  syncTaskNotifications(s)
  return true
end
local function startRequestedSuspend(s)
  if not s.suspendRequested or s.uninstall then return end
  for _,f in pairs(s.factories) do
    if f.upgradeTarget then return end
  end
  s.uninstall={status="running",mode="suspend",cleaned=0,remaining=0}
  if beginSuspend(s) then s.suspendRequested=nil
  else
    s.suspendRequested=nil;s.uninstall.status="blocked";s.uninstall.reason="busy"
  end
end
local function initialize(state)
  local s=state:get()
  if not s or not s.version then s=core.newState() end
  if s.version<2 then
    -- Same route key and levels: old saves only need availability refreshed.
    for _,f in pairs(s.factories) do
      local info=inspect(f.entity)
      if info then
        f.supported=info.supported;f.pending=nil;f.revision=f.revision+1
        core.sweep(s,f)
      end
    end
    s.version=2
  end
  if not state:hasEventSubscriptions() then
    for _,e in ipairs({"production_migrate","open","accept","cancel","upgrade","upgrade_step","upgrade_failure_seen","reset","prepare_uninstall","retry_uninstall","uninstall_step","OnCalcTicketPrice","OnToArriveAtDestination"}) do state:subscribeToEvent(e) end
  end
  if not s.uninstallResumeStepSubscribed then
    -- Existing saves have an event subscription set already, so the general
    -- hasEventSubscriptions() branch cannot add this new cleanup event.
    s.uninstallResumeStepSubscribed=true
    state:subscribeToEvent("uninstall_resume_step")
  end
  if not uninstallSessionInitialized then
    -- Proposal callbacks can be lost across a save reload. Rescan rather
    -- than waiting for a callback that can no longer arrive.
    if s.uninstall and (s.uninstall.status=="running" or s.uninstall.status=="restoring") then
      s.uninstall.inFlight=nil
      s.uninstall.queuedAt=nil
    end
    uninstallSessionInitialized=true
  end
  if not s.uninstallSubscribed then
    s.uninstallSubscribed=true
    state:subscribeToEvent("prepare_uninstall")
    state:subscribeToEvent("retry_uninstall")
    state:subscribeToEvent("uninstall_step")
  end
  if not s.suspendSubscribed then
    s.suspendSubscribed=true
    state:subscribeToEvent("resume_mod")
  end
  if s.productionSubscribed~=5 then
    s.productionSubscribed=5
    state:subscribeToEvent("production_migrate")
    for _,f in pairs(s.factories)do f.productionReward=nil end
  end
  if not s.upgradeStepSubscribed then
    s.upgradeStepSubscribed=true
    state:subscribeToEvent("upgrade_step")
  end
  if not s.upgradeFailureSeenSubscribed then
    s.upgradeFailureSeenSubscribed=true
    state:subscribeToEvent("upgrade_failure_seen")
  end
  for _,f in pairs(s.factories) do
    core.migrateUpgradeQueue(f)
    if f.migrationStrategyVersion~=MIGRATION_STRATEGY_VERSION then
      f.migrationStrategyVersion=MIGRATION_STRATEGY_VERSION
      f.migrationBuildAttempted=nil;f.migrationBuildFailed=nil
      f.migrationTrimKey=nil;f.migrationTrimCount=nil;f.migrationClearVersion=nil
    end
    if f.firstStandardUsed==nil then
      f.firstStandardUsed=(f.task and (f.task.tier or 1)==1) or
        (f.lastCompletedTask and (f.lastCompletedTask.tier or 1)==1) or false
    end
    core.reprice(f)
  end
  if not s.upgradeRecoveryVersion then prepareUpgradeRecovery(s) end
  return s
end
function data()
  return {
    update=function(_,state,dt)
      local s=initialize(state)
      if not s.initialized then seedSubsidies(s) end
      if dt>0 and s.initialized then
        local gt=api.engine.getComponent(api.engine.util.getWorld(),CT.GAME_TIME)
        local recovery=s.upgradeRecovery
        if recovery then
          recovery.startedAt=recovery.startedAt or gt.gameTime
          if gt.gameTime-recovery.startedAt>=5000 then
            recoverUpgrades(s,recovery.factories);s.upgradeRecovery=nil
          end
        end
        if not notificationsInitialized then
          notificationsInitialized=true
          syncTaskNotifications(s)
        end
        if s.uninstall then
          local u=s.uninstall
          if (u.status=="running" or u.status=="restoring") and (not u.queuedAt or gt.gameTime-u.queuedAt>=5000) then
            u.queuedAt=gt.gameTime;state:set(s)
            api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("",PREFIX,"uninstall_resume_step",{}))
            return
          end
          state:set(s)
          return
        end
        if not s.lastPoll or gt.gameTime-s.lastPoll>=1000 then
          s.lastPoll=gt.gameTime; pollSubsidies(s)
          if not s.suspendRequested then productionTick(s,gt.gameTime) end
          -- Replacement proposals may change entity IDs. Rediscover by the
          -- persisted growth ID, not by position or a mutable display name.
          local relink=false
          local taskInvalidated=false
          for _,f in pairs(s.factories) do
            if f.needsRelink or not component(f.entity,CT.INDUSTRY) then relink=true end
          end
          if relink then
            api.engine.forEachEntityWithComponent(function(e)
              local ce,con=constructionFor(e)
              local par=con and paramsOf(con); local id=par and par.spy_growth_id
              local f=id and s.factories[id]
              if f then f.entity=e; f.construction=ce; f.needsRelink=nil end
            end,CT.INDUSTRY)
          end
          for _,f in pairs(s.factories) do
            if component(f.entity,CT.INDUSTRY) then syncWorkerBoost(f.entity) end
            if f.task and not f.busy then
              local info=inspect(f.entity)
              local available=info and (f.task.kind~="workers" or info.available.workers)
              if not available then
                f.task=nil; f.seenCargo={}; f.revision=f.revision+1;taskInvalidated=true
                if info then refresh(f,info) end
              end
            end
          end
          if taskInvalidated then syncTaskNotifications(s) end
        end
        for _,f in pairs(s.factories) do
          if f.upgradeTarget and not f.busy and not f.needsRelink and
            (not f.upgradeStepQueued or gt.gameTime-(f.upgradeStepQueuedAt or 0)>=5000) then
            f.upgradeStepQueued=true;f.upgradeStepQueuedAt=gt.gameTime
            api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("",PREFIX,"upgrade_step",{factoryId=f.id}))
          end
        end
        startRequestedSuspend(s)
      end
      state:set(s)
    end,
    handleEvent=function(_,state,src,id,name,p)
      local s=initialize(state)
      if src=="" and id=="" and (name=="handleLegacy" or name=="initNewGame") then
        prepareUpgradeRecovery(s);state:set(s);return
      end
      if id==PREFIX and name=="prepare_uninstall" then
        if not s.uninstall then s.suspendRequested=true;startRequestedSuspend(s) end
        state:set(s);return
      elseif id==PREFIX and name=="retry_uninstall" then
        if s.uninstall and s.uninstall.status=="blocked" then
          if s.uninstall.mode~="suspend" or s.uninstall.restoring or beginSuspend(s) then
            s.uninstall.status=s.uninstall.restoring and "restoring" or "running"
            s.uninstall.reason=nil;s.uninstall.blockedEntity=nil;s.uninstall.queuedAt=nil
          end
        end
        state:set(s);return
      elseif id==PREFIX and name=="resume_mod" then
        if s.uninstall and s.uninstall.mode=="suspend" and s.uninstall.status=="disabled" then
          s.uninstall.status="restoring";s.uninstall.restoring=true;s.uninstall.cleaned=0;s.uninstall.queuedAt=nil
        end
        state:set(s);return
      elseif id==PREFIX and (name=="uninstall_step" or name=="uninstall_resume_step") then
        local gt=api.engine.getComponent(api.engine.util.getWorld(),CT.GAME_TIME)
        if uninstallTick(state,s,gt.gameTime) then return end
        state:set(s);return
      elseif s.uninstall then state:set(s);return end
      if id==PREFIX and name=="production_migrate" then p.action="open";if action(state,s,p)then return end
      elseif id==PREFIX then p.action=name; if action(state,s,p) then return end
      elseif id=="TransportVehicleSystem" and name=="OnCalcTicketPrice" then onCargo(s,p)
      elseif id=="SimPersonSystem" and name=="OnToArriveAtDestination" then onWorkers(s,p) end
      state:set(s)
    end,
  }
end
