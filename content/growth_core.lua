-- Pure rules: no engine calls. State is serializable and owned by growth.gs.
local M = {}
-- Editable balance settings shared by simulation and GUI. Monetary values are
-- fixed base prices; calendar year and company rank do not affect payments.
M.config={pointPrice=100000,overflowRatio=3,
  firstStandardTargetMultiplier=0.5,firstStandardCostMultiplier=0.5,
  resetPointPrice=20000,resetMinimum=200000,
  throughputPerLevel=0.08,extraOutputEveryLevels=5,extraOutputPerStep=1,boostPerLevel=0.1,
  environmentPerLevel=0.08,
  loadingPerLevel=0.4,storagePerLevel=0.2,
  jobsPerLevel=0.3,jobDestinationWeightPerLevel=1.0,
  speedPerLevel=4,speedLimit=50,
  bonusStockTagBase=1900000000,
  taskNotificationDurationMs=60000}
-- Shared by the simulation award and vanilla subsidy reward text.
M.subsidyReward = 30
M.townSubsidyReward = 30
function M.extraOutput(level)
  return math.floor(math.max(0,level or 0)/M.config.extraOutputEveryLevels)*M.config.extraOutputPerStep
end
function M.environmentReduction(level)
  local n=math.max(0,math.min(10,level or 0))
  local reduction=n*M.config.environmentPerLevel
  return reduction>=1-1e-9 and 1 or reduction
end
-- Diagnostic worker history, independent of the native 20-visitor cap.
function M.trackWorkerVisit(factory,person,now,limit,interval,seed,same)
  local previous=factory.workerVisitors or seed or {}
  local visitors={{time=now,entity=M.copy(person)}}
  local cutoff=now-interval
  for _,visit in ipairs(previous) do
    if visit.time and visit.time>=cutoff and visit.entity and
        not same(visit.entity,person) and #visitors<limit then
      visitors[#visitors+1]=M.copy(visit)
    end
  end
  factory.workerVisitors=visitors
end
function M.workerVisitCount(factory,now,interval,limit)
  if not factory or not factory.workerVisitors then return nil end
  local count=0;local cutoff=now-interval
  for _,visit in ipairs(factory.workerVisitors) do
    if visit.time and visit.time>=cutoff then count=count+1 end
  end
  return math.min(count,limit)
end
M.factorySubsidies = {
  ["::/game_mechanics/subventions/deliver_cargo/deliver_cargo.res"]=true,
  ["::/game_mechanics/subventions/deliver_workers/deliver_workers.res"]=true,
}
M.townSubsidies = {
  ["::/game_mechanics/subventions/deliver_cargo_town/deliver_cargo_town.res"]=true,
  ["::/game_mechanics/subventions/deliver_passengers/deliver_passengers.res"]=true,
}
function M.subsidyKey(t)
  return tostring(t.id).."|"..tostring(t.uid).."|"..tostring(t.spawnTime)
end
function M.subsidyTarget(t)
  local d=t.data or {}; local v=d.stockListEntity or d.to
  return v and v.entity
end
M.routes = {
  {key="production", name="growth_production", max=15},
  {key="boost", name="growth_boost", max=10},
  {key="environment", name="growth_environment", max=10},
  {key="logistics", name="growth_logistics", max=5},
  {key="storage", name="growth_storage", max=5},
  {key="jobs", name="growth_jobs", max=5},
}
M.tiers = {
  {factor=4, boostFactor=2, reward=12},
  {factor=8, boostFactor=4, reward=30},
  {factor=14, boostFactor=7, reward=60},
}
M.ranges = {{10,50},{50,100},{75,150},{150,300}}
function M.copy(v)
  if type(v)~="table" then return v end
  local r={}; for k,x in pairs(v) do r[k]=M.copy(x) end
  -- Native construction results contain typed matrices. Module updates run
  -- after our wrapper and still need their arithmetic metamethods.
  local mt=getmetatable(v)
  if type(mt)=="table" then setmetatable(r,mt) end
  return r
end
-- Detect supported modes for the road-speed UI, not connected roads/lines.
-- Loading upgrades use the same rate for every transport mode.
function M.hasRoadTransport(def)
  local road,known=false,false
  local function modes(list)
    for _,mode in ipairs(list or {})do
      if mode=="TRUCK" or mode=="BUS" or mode=="CAR" then road=true;known=true
      elseif mode~="PERSON" and mode~="CARGO" then known=true end
    end
  end
  local config=def and def.terminalConfig
  if config then for _,key in ipairs({"terminals","terminals2"})do
    for _,terminal in ipairs(config[key] or {})do modes(terminal.mode)end
  end end
  for _,sub in ipairs(def and def.subconstructions or {})do
    for _,lane in ipairs(sub.laneLists or {})do modes(lane.transportModes)end
    for _,terminal in ipairs(sub.station and sub.station.terminals or {})do modes(terminal.transportModes)end
  end
  if road then return true end
  if known then return false end
end
function M.newState()
  return {version=2, factories={}, overflow=0, nextId=1, subsidySeen={}}
end
function M.newFactory(id)
  local f={id=id, points=0, levels={}, supported={}, revision=0, candidates={}, seenCargo={},firstStandardUsed=false}
  for _,r in ipairs(M.routes) do f.levels[r.key]=0 end
  return f
end
function M.route(key)
  for _,r in ipairs(M.routes) do if r.key==key then return r end end
end
function M.spent(f)
  local n=0; for _,r in ipairs(M.routes) do local l=f.levels[r.key] or 0; n=n+l*(l+1)/2 end
  return n
end
-- The target includes all reserved upgrades, including the in-flight snapshot.
function M.commitUpgrade(f,batch)
  f.levels=M.copy(batch.levels)
  local target=f.upgradeTarget
  target.own=target.own-batch.own;target.global=target.global-batch.global
  if target.own==0 and target.global==0 then f.upgradeTarget=nil end
  f.upgradeBatch=nil
end
-- Convert old saved click queues once; normal operation keeps no click list.
function M.migrateUpgradeQueue(f)
  local queue=f.upgradeQueue
  if not queue then return end
  if #queue>0 and not f.upgradeTarget then
    local target={levels=M.copy(f.levels),own=0,global=0}
    local oldBatch=f.upgradeBatch
    local count=f.busy and (oldBatch and oldBatch.count or 1) or 0
    local batch={own=0,global=0}
    for i,click in ipairs(queue) do
      target.levels[click.route]=(target.levels[click.route] or 0)+1
      target.own=target.own+(click.own or 0);target.global=target.global+(click.global or 0)
      if i<=count then
        batch.own=target.own;batch.global=target.global
        batch.levels=M.copy(target.levels)
      end
    end
    f.upgradeTarget=target
    f.upgradeBatch=count>0 and batch or nil
  end
  f.upgradeQueue=nil
end
function M.isMax(f)
  local any=false
  for _,r in ipairs(M.routes) do
    -- A future pending route is distinct from an inapplicable route.
    if f.pending and f.pending[r.key] then return false end
    if f.supported[r.key] then any=true; if (f.levels[r.key] or 0)<r.max then return false end end
  end
  return any
end
function M.sweep(s,f)
  if M.isMax(f) and f.points>0 then s.overflow=s.overflow+f.points; f.points=0 end
end
function M.award(s,f,n)
  assert(n>=0 and n==math.floor(n)); f.points=f.points+n; M.sweep(s,f); f.revision=f.revision+1
end
function M.payment(s,f,key)
  local r=M.route(key)
  if not r or not f.supported[key] then return nil,"unsupported" end
  local l=f.levels[key] or 0
  if l>=r.max then return nil,"max" end
  local cost=l+1; local own=math.min(f.points,cost); local global=(cost-own)*M.config.overflowRatio
  if s.overflow<global then return nil,"points" end
  return {cost=cost, own=own, global=global}
end
function M.upgrade(s,f,key)
  local p,err=M.payment(s,f,key); if not p then return nil,err end
  f.points=f.points-p.own; s.overflow=s.overflow-p.global
  f.levels[key]=(f.levels[key] or 0)+1; f.revision=f.revision+1; M.sweep(s,f)
  return p
end
function M.resetCost(f) return math.floor(math.max(M.config.resetMinimum,M.spent(f)*M.config.resetPointPrice)) end
function M.taskCost(reward,firstStandard)
  local cost=reward*M.config.pointPrice*(firstStandard==true and M.config.firstStandardCostMultiplier or 1)
  return math.floor(cost)
end
local function firstStandard(f,tier) return tier==1 and not f.firstStandardUsed end
local function offerTarget(f,tier,baseTarget)
  if firstStandard(f,tier) then
    return math.max(1,math.ceil(baseTarget*M.config.firstStandardTargetMultiplier))
  end
  return baseTarget
end
-- Rebalance existing offers from their original goals. Accepted contracts
-- retain their agreed target, reward and paid fee across balance changes.
function M.reprice(f)
  if f.task then return end
  local changed=false
  for tier,c in ipairs(f.candidates or {}) do
    local baseTarget=c.baseTarget or c.target
    local target=offerTarget(f,tier,baseTarget)
    local reward=M.tiers[tier].reward;local cost=M.taskCost(reward,firstStandard(f,tier))
    if c.baseTarget~=baseTarget or c.target~=target or c.reward~=reward or c.cost~=cost then
      c.baseTarget=baseTarget;c.target=target;c.reward=reward;c.cost=cost;changed=true
    end
  end
  if changed then f.revision=f.revision+1 end
end
-- Keep the existing random draw and task choices when balance settings change.
-- Accepted contracts keep their original target and eligibility.
function M.retargetOffers(f,boostOnly)
  if f.task then return end
  local changed=false
  local legacyFactors={4,8,15}
  for tier,c in ipairs(f.candidates or {})do
    local old=c.factor or legacyFactors[tier]
    if c.kind=="supply" and boostOnly then c.kind="boost";changed=true end
    local t=M.tiers[tier]
    local factor=(c.kind=="workers" or c.kind=="boost") and t.boostFactor or t.factor
    if factor~=old then
      c.baseTarget=math.max(1,math.floor((c.baseTarget or c.target)*factor/old+0.5))
      c.target=offerTarget(f,tier,c.baseTarget);changed=true
    end
    c.factor=factor
  end
  M.reprice(f)
  if changed then f.revision=f.revision+1 end
end
function M.reset(s,f)
  local refund=M.spent(f)
  for _,r in ipairs(M.routes) do f.levels[r.key]=0 end
  -- Global currency has already been exchanged. Refund only local skill points.
  f.points=f.points+refund; f.revision=f.revision+1
  return refund
end
function M.generate(f, available, risk, workers, random)
  random=random or math.random
  local types={}; for _,k in ipairs({"supply","products","workers","boost"}) do if available[k] then types[#types+1]=k end end
  local pool=M.copy(types); f.candidates={}
  if #pool==0 then return end
  for tier,t in ipairs(M.tiers) do
    if #pool==0 then pool=M.copy(types) end
    local idx=random(1,#pool); local kind=table.remove(pool,idx)
    local range=M.ranges[math.max(1,math.min(4,(risk or 1)+1))]
    local target
    local factor=(kind=="workers" or kind=="boost") and t.boostFactor or t.factor
    if kind=="workers" then target=math.max(1,math.ceil(workers))*factor
    else target=random(range[1]*factor,range[2]*factor) end
    f.candidates[tier]={kind=kind,baseTarget=target,target=offerTarget(f,tier,target),factor=factor,
      reward=t.reward,cost=M.taskCost(t.reward,firstStandard(f,tier)),tier=tier}
  end
  f.revision=f.revision+1
end
function M.accept(f,tier)
  if f.task then return nil,"active" end
  local c=f.candidates[tier]; if not c then return nil,"candidate" end
  f.nextTaskId=(f.nextTaskId or 0)+1
  f.task=M.copy(c); f.task.uid=f.id..":"..f.nextTaskId; f.task.progress=0; f.candidates={}; f.seenCargo={}; f.revision=f.revision+1
  if tier==1 then f.firstStandardUsed=true end
  return f.task
end
function M.progress(s,f,kind,n,token)
  local t=f.task; if not t or t.kind~=kind then return false end
  if token then if f.seenCargo[token] then return false end; f.seenCargo[token]=true end
  t.progress=math.min(t.target,t.progress+n)
  if t.progress>=t.target then local reward=t.reward; f.lastCompletedTask=M.copy(t); f.task=nil; f.seenCargo={}; M.award(s,f,reward); return true end
  return false
end
return M
