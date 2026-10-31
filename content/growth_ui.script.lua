local react=ug_require("::/gui/main/react.lua")
local builtin=ug_require("::/gui/main/builtin.lua")
local engine=ug_require("::/gui/main/engine_react_util.tl")
local card=ug_require("::/gui/main/content_card.tl")
local dialogs=ug_require("::/gui/menu/dialog_react_util.tl")
local core=ug_require("spy_industry_evolution::/growth_core.lua")
local taskUi=ug_require("spy_industry_evolution::/growth_task_ui.lua")
local cfg=core.config
local CT=api.type.ComponentType
local watchedFactories={}
local watchedGameCtx
local workerHooks=ug_require("spy_industry_evolution::/growth_worker_hooks.lua")
workerHooks.install()
workerHooks.installProgress()
ug_require("spy_industry_evolution::/growth_worker_ui.lua").install()
local function read(entity)
  local id=api.engine.system.gameScriptSystem.getEntityForGameScript("spy_industry_evolution::/growth.gs")
  if not id or id<0 then return nil end
  local c=api.engine.getComponent(id,CT.GAME_SCRIPT); if not c then return nil end
  local s=c.state_native and c.state_native:asTable() or c.state
  if not s or not s.factories then return nil end
  for _,f in pairs(s.factories) do if f.entity==entity then return {factory=f,overflow=s.overflow,
    uninstall=s.uninstall,suspendRequested=s.suspendRequested} end end
  if s.uninstall or s.suspendRequested then return {uninstall=s.uninstall,suspendRequested=s.suspendRequested} end
end
local function send(entity,action,extra)
  local data=read(entity); local p=extra or {}; p.entity=entity
  if p.revision==nil then p.revision=data and data.factory and data.factory.revision end
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("","spy_industry_evolution",action,p))
end
local function text(s,class,tooltip)
  return builtin.TextView{text=s,meta={class="font-scale-body, "..(class or ""),tooltip=tooltip}}
end
local function button(s,click,enabled,class,tooltip,ref)
  local p={content=text(s),onClick=click,
    meta={enabled=enabled~=false,class="spy-growth-button, "..(class or ""),tooltip=tooltip}}
  return ref and builtin.Button(react.ref(ref),p) or builtin.Button(p)
end
local function box(children,class,horizontal)
  return builtin.Component{meta={class=class},layout=builtin.BoxLayout{
    orientation=horizontal and builtin.type.Orientation.Horizontal or builtin.type.Orientation.Vertical,children=children}}
end
local function row(children,class) return box(children,class,true) end
local function tableRow(cells,weights)
  return builtin.Component{layout=builtin.TableLayout{columnWeights=weights,rows={builtin.Row{cells=cells}}}}
end
local icons={production="production_iteration",boost="production_booster",environment="symbol_pollution",
  logistics="symbol_speed",storage="symbol_cargo",jobs="symbol_person_multiple"}
local function icon(key)
  return builtin.ImageView{path="::/gui/entity_window/icons/"..icons[key]..".tga",meta={class="spy-growth-icon"}}
end
local function number(n)
  return string.format("%.2f",n):gsub("0+$",""):gsub("%.$","")
end
local function effectRows(key,level,nextLevel,available,hasRoadTransport)
  local rows={}
  local function effect(label,current,after,unit)
    local delta=after-current
    local value=function(n)return "+"..number(n)..unit end
    rows[#rows+1]=tableRow({text(_(label),"spy-growth-effect-name"),
      text(value(current),"spy-growth-current"),
      text(available and value(delta) or "—","spy-growth-change"),
      text(available and value(after) or "—","spy-growth-next")},{1,-1,-1,-1})
  end
  if key=="production" then
    effect("growth_effect_throughput",cfg.throughputPerLevel*100*level,cfg.throughputPerLevel*100*nextLevel,"%")
    effect("growth_effect_yield",core.extraOutput(level),core.extraOutput(nextLevel),"")
  elseif key=="boost" then
    effect("growth_effect_boost",cfg.boostPerLevel*100*level,cfg.boostPerLevel*100*nextLevel,"%")
  elseif key=="environment" then
    effect("growth_effect_pollution",core.environmentReduction(level)*100,core.environmentReduction(nextLevel)*100,"%")
    effect("growth_effect_noise",core.environmentReduction(level)*100,core.environmentReduction(nextLevel)*100,"%")
  elseif key=="logistics" then
    local rate=cfg.loadingPerLevel
    effect("growth_effect_loading",rate*100*level,rate*100*nextLevel,"%")
    if hasRoadTransport~=false then effect("growth_effect_speed",cfg.speedPerLevel*level,cfg.speedPerLevel*nextLevel," km/h")end
  elseif key=="storage" then
    effect("growth_effect_storage",cfg.storagePerLevel*100*level,cfg.storagePerLevel*100*nextLevel,"%")
  else
    effect("growth_effect_jobs",cfg.jobsPerLevel*100*level,cfg.jobsPerLevel*100*nextLevel,"%")
    effect("growth_effect_destination_weight",cfg.jobDestinationWeightPerLevel*100*level,
      cfg.jobDestinationWeightPerLevel*100*nextLevel,"%")
  end
  return rows
end
local function description(key,hasRoadTransport)
  if key=="production" then return _("growth_production_effect") end
  if key=="boost" then return _("growth_boost_effect") end
  if key=="logistics" and hasRoadTransport~=false then return _("growth_logistics_effect") end
  if key=="jobs" then return _("growth_jobs_effect") end
end
-- A dedicated recipe lets us close only this mod's confirmation window.
local ConfirmDialog=react.RegisterWrapperRecipe("SpyGrowthConfirmDialog",dialogs.DialogWindow,function(p)
  return dialogs.DialogWindow(p)
end)
local FailureDialog=react.RegisterWrapperRecipe("SpyGrowthUpgradeFailureDialog",dialogs.DialogWindow,function(p)
  return dialogs.DialogWindow(p)
end)
local ErrorDialog=react.RegisterWrapperRecipe("SpyGrowthActionErrorDialog",dialogs.DialogWindow,function(p)
  return dialogs.DialogWindow(p)
end)
local ApplyingDialog=react.RegisterWrapperRecipe("SpyGrowthApplyingDialog",dialogs.DialogWindow,function(p)
  return dialogs.DialogWindow(p)
end)
local function windowApi(param) return param.gameCtx.windowContainer:get():getApi() end
local function closeConfirmation(param) windowApi(param).removeAllWindows(ConfirmDialog) end
local alertedFailures={}
local alertedErrors={}
local actionPositions={}
local applyingFactoryId
local function positionOf(ref)
  local ok,pos=pcall(function()return ref:get():getPosition(1.0,0.0)end)
  if ok and pos and type(pos.x)=="number" and type(pos.y)=="number" then
    return {x=pos.x,y=pos.y}
  end
end
local function dialogPosition(factoryId)
  local pos=actionPositions[factoryId]
  return pos and pos.x or 0.5,pos and pos.y or 0.5
end
local function showActionError(param,f)
  local version=f.errorVersion or f.revision
  if not f.error or f.busy or alertedErrors[f.id]==version then return end
  local x,y=dialogPosition(f.id)
  windowApi(param).addSingletonWindow(ErrorDialog,{
    x=x,y=y,closable=true,windowClass="spy-growth-dialog",
    windowTitle=_("growth_error_title"),displayText=_(f.error),
    onClose=function()windowApi(param).removeAllWindows(ErrorDialog)end,
    choices={{text=_("growth_confirm"),onClick=function()end}}
  })
  alertedErrors[f.id]=version
end
local function syncApplyingDialog(param,f)
  local active=f and f.busy and not f.upgradeTarget
  if applyingFactoryId and (not active or applyingFactoryId~=f.id) then
    windowApi(param).removeAllWindows(ApplyingDialog);applyingFactoryId=nil
  end
  if active and applyingFactoryId~=f.id then
    local x,y=dialogPosition(f.id)
    windowApi(param).addSingletonWindow(ApplyingDialog,{
      x=x,y=y,closable=false,windowClass="spy-growth-dialog",
      windowTitle=_("growth_title"),displayText=_("growth_applying"),
      onClose=function()windowApi(param).removeAllWindows(ApplyingDialog)end,
      choices={}
    })
    applyingFactoryId=f.id
  end
end
local function showUpgradeFailure(param,f)
  local failure=f.upgradeFailure
  if not failure or failure.seen or
    (alertedFailures[f.id] or 0)>=(failure.version or failure.ticket) then return end
  local route=core.route(failure.route)
  local name=route and _(route.name) or tostring(failure.route)
  local reason=_('growth_upgrade_failure_'..tostring(failure.reason or 'build'))
  local result=failure.restored and _("growth_upgrade_failure_restored") or
    _("growth_upgrade_failure_unverified")
  local detail=failure.batch and string.format(_("growth_upgrade_failure_batch_detail"),reason,result) or
    string.format(_("growth_upgrade_failure_detail"),name,failure.level,reason,result)
  windowApi(param).addSingletonWindow(FailureDialog,{
    x=0.5,y=0.5,closable=true,windowClass="spy-growth-dialog",
    windowTitle=_("growth_upgrade_failure_title"),
    displayText=detail,
    onClose=function()windowApi(param).removeAllWindows(FailureDialog)end,
    choices={{text=_("growth_confirm"),onClick=function()end}}
  })
  alertedFailures[f.id]=failure.version or failure.ticket
  send(param.entityId,"upgrade_failure_seen",{factoryId=f.id,version=failure.version})
end
local function askConfirmation(param,f,request)
  local wc=windowApi(param)
  local revision=f.revision
  wc.addSingletonWindow(ConfirmDialog,{
    x=0.5,y=0.5,closable=true,windowClass="spy-growth-dialog",
    windowTitle=_("growth_confirm").." · ".._("growth_title"),displayText=request.label,
    onClose=function()closeConfirmation(param)end,onBackChoiceIndex=2,
    choices={
      {text=_("growth_confirm"),enabled=request.action=="prepare_uninstall" or not f.busy,onClick=function()
        local current=read(param.entityId)
        if not current or not current.factory or current.uninstall or current.suspendRequested then return end
        local active=current.factory
        if request.action~="prepare_uninstall" and
          (active.busy or active.upgradeTarget) then return end
        if request.action~="prepare_uninstall" and active.revision~=revision then return end
        send(param.entityId,request.action,{tier=request.tier,route=request.route,revision=revision})
      end},
      {text=_("growth_back"),isSecondary=true,onClick=function()end}
    }
  })
end
local panel=react.RegisterRecipe("SpyIndustryGrowth",function(param)
  local selectedTab=react.useState("upgrades")
  local optimism=react.useState({})
  local resetButtonRef=react.useNodeRef()
  local data=engine.useStepState(function()return read(param.entityId) or {} end):old()
  react.onStep(function()
    local current=read(param.entityId)
    local f=current and current.factory
    syncApplyingDialog(param,f)
    if f then showUpgradeFailure(param,f);showActionError(param,f) end
    if current and (current.suspendRequested or f and
      (f.busy or f.upgradeTarget)) then
      closeConfirmation(param);taskUi.close(param)
    end
  end)
  react.onMount(function() send(param.entityId,"open") end)
  react.onUnmount(function()
    closeConfirmation(param);windowApi(param).removeAllWindows(FailureDialog)
    windowApi(param).removeAllWindows(ErrorDialog)
    windowApi(param).removeAllWindows(ApplyingDialog);applyingFactoryId=nil;taskUi.close(param)
  end)
  if data and data.suspendRequested then
    return builtin.BoxLayout{children={card.ContentCard{meta={localKey="spyIndustryGrowth"},title=_("growth_title"),
      initialCalloutTextPermanent="",hasPermanentFocusables=true,gameCtx=param.gameCtx,
      showOnRightSide=param.showCalloutOnRightSide,
      extraChildrenPermanent={box({text(_("growth_uninstall_waiting"))},"spy-growth-root")}}}}
  end
  if data and data.uninstall then
    local u=data.uninstall;local children={}
    if u.status=="disabled" then
      children[#children+1]=text(_("growth_uninstall_disabled"))
      children[#children+1]=button(_("growth_uninstall_resume"),function()
        send(param.entityId,"resume_mod")
      end,true,"primary")
    elseif u.status=="ready" then
      children[#children+1]=text(_("growth_uninstall_ready"))
    elseif u.status=="blocked" then
      local reason=_("growth_uninstall_reason_"..tostring(u.reason or "proposal"))
      children[#children+1]=text(string.format(_("growth_uninstall_blocked"),
        tostring(u.blockedEntity or "?"),reason))
      children[#children+1]=button(_("growth_uninstall_retry"),function()
        send(param.entityId,"retry_uninstall")
      end,true,"primary")
    elseif u.status=="restoring" then
      children[#children+1]=text(string.format(_("growth_uninstall_restoring"),u.cleaned or 0))
    else
      children[#children+1]=text(string.format(_("growth_uninstall_running"),
        u.cleaned or 0,u.remaining or 0))
    end
    return builtin.BoxLayout{children={card.ContentCard{meta={localKey="spyIndustryGrowth"},title=_("growth_title"),
      initialCalloutTextPermanent="",hasPermanentFocusables=true,gameCtx=param.gameCtx,
      showOnRightSide=param.showCalloutOnRightSide,
      extraChildrenPermanent={box(children,"spy-growth-root")}}}}
  end
  if not data or not data.factory then return builtin.BoxLayout{children={}} end
  local f=data.factory; local children={}
  watchedFactories[f.id]=true;watchedGameCtx=param.gameCtx
  local function projected(source,preview)
    local factory=source.factory
    local view=core.copy(factory)
    local trial={overflow=source.overflow}
    view.levels=core.copy(factory.upgradeTarget and factory.upgradeTarget.levels or factory.levels)
    local pending=preview.factoryId==factory.id and preview.ticket>(factory.upgradeTicket or 0) and
      preview.failureEpoch==(factory.upgradeFailure and factory.upgradeFailure.version or 0)
    if pending then
      -- Only one local target is needed. Price the part not yet acknowledged.
      local levels=core.copy(view.levels)
      for _,route in ipairs(core.routes) do
        levels[route.key]=math.max(levels[route.key] or 0,preview.levels[route.key] or 0)
      end
      local cost=core.spent({levels=levels})-core.spent(view)
      local own=math.min(view.points,cost)
      local shared=(cost-own)*cfg.overflowRatio
      if trial.overflow>=shared then
        view.levels=levels;view.points=view.points-own;trial.overflow=trial.overflow-shared
      end
    end
    core.sweep(trial,view)
    return view,trial.overflow,pending
  end
  local display,displayOverflow,pendingClick=projected(data,optimism:old())
  local spent=core.spent(f);local resetCost=core.resetCost(f)
  local locked=f.busy or f.upgradeTarget or pendingClick
  children[#children+1]=text(_("growth_points_title"),"spy-growth-points-heading")
  children[#children+1]=tableRow({
    box({text(_("growth_local_label"),"spy-growth-muted"),text(tostring(display.points),"spy-growth-number")},"spy-growth-balance"),
    box({text(_("growth_global_label"),"spy-growth-muted"),text(tostring(displayOverflow),"spy-growth-number")},"spy-growth-balance"),
    row({
      button(_("growth_reset"),function()
        actionPositions[f.id]=positionOf(resetButtonRef)
        askConfirmation(param,f,{action="reset",label=string.format(_("growth_confirm_reset"),api.util.formatMoney(resetCost),spent)})
      end,spent>0 and not locked,"spy-growth-reset, primary",nil,resetButtonRef),
      button(_("growth_uninstall_button"),function()
        askConfirmation(param,f,{action="prepare_uninstall",label=_("growth_uninstall_confirm")})
      end,not pendingClick and (not f.busy or f.upgradeTarget~=nil),
        "spy-growth-reset, primary")
    },"spy-growth-actions")
  },{1,1,-1})
  children[#children+1]=text(string.format(_("growth_exchange_hint"),cfg.overflowRatio),"spy-growth-muted")
  children[#children+1]=tableRow({
    button(_("growth_upgrade_tab"),function()selectedTab:set("upgrades");closeConfirmation(param);taskUi.close(param)end,true,
      "spy-growth-tab, "..(selectedTab:old()=="upgrades" and "spy-growth-selected" or "")),
    button(_("growth_task_tab"),function()selectedTab:set("tasks");closeConfirmation(param);taskUi.close(param)end,true,
      "spy-growth-tab, "..(selectedTab:old()=="tasks" and "spy-growth-selected" or ""))
  },{1,1})
  if selectedTab:old()=="upgrades" then
  children[#children+1]=tableRow({text(_("growth_effect_label"),"spy-growth-effect-name"),
    text(_("growth_current_label"),"spy-growth-current"),text(_("growth_change_label"),"spy-growth-change-label"),
    text(_("growth_next_label"),"spy-growth-next-label")},{1,-1,-1,-1})
  for routeIndex,r in ipairs(core.routes) do
    local level=display.levels[r.key] or 0; local payment=core.payment({overflow=displayOverflow},display,r.key)
    local enabled=not not (display.supported[r.key] and level<r.max and payment and
      (not f.busy or f.upgradeTarget))
    local costLabel=level>=r.max and _("growth_max") or string.format(_("growth_points_cost"),level+1)
    if not f.supported[r.key] then costLabel=_("growth_unavailable") end
    local routeChildren={tableRow({
      row({icon(r.key),text(_(r.name),"spy-growth-route-name")},"spy-growth-route-heading"),
      text(level.." / "..r.max,"spy-growth-level"),text(costLabel,"spy-growth-cost"),button(_("growth_upgrade_button"),function()
      local latest=read(param.entityId)
      if not latest or not latest.factory or latest.factory.id~=f.id then return end
      if latest.factory.busy and not latest.factory.upgradeTarget then return end
      local previous=optimism:old()
      local current,currentOverflow=projected(latest,previous)
      if not core.payment({overflow=currentOverflow},current,r.key) then return end
      local ticket=math.max(latest.factory.upgradeTicket or 0,
        previous.factoryId==f.id and previous.ticket or 0)+1
      local failureEpoch=latest.factory.upgradeFailure and latest.factory.upgradeFailure.version or 0
      current.levels[r.key]=(current.levels[r.key] or 0)+1
      optimism:set({factoryId=f.id,ticket=ticket,failureEpoch=failureEpoch,levels=current.levels})
      send(param.entityId,"upgrade",{factoryId=f.id,route=r.key,ticket=ticket,
        failureEpoch=failureEpoch})
    end,enabled,"spy-growth-upgrade, primary",description(r.key,f.hasRoadTransport))},{1,-1,-1,-1})}
    for _,effect in ipairs(effectRows(r.key,level,math.min(r.max,level+1),f.supported[r.key],f.hasRoadTransport)) do
      routeChildren[#routeChildren+1]=effect
    end
    children[#children+1]=box(routeChildren,"spy-growth-route, "..(not f.supported[r.key] and "spy-growth-unavailable" or ""))
  end
  else
  if f.task then
    local t=f.task
    local taskChildren={text(taskUi.listTitle(t),"spy-growth-task-tier"),
      text(taskUi.goal(t,param.entityId),"spy-growth-route-name")}
    if taskUi.noCargoTypes(t,param.entityId) then
      taskChildren[#taskChildren+1]=text(_("growth_task_no_cargo"),"spy-growth-task-hint")
    end
    taskChildren[#taskChildren+1]=builtin.ProgressBar{value=t.progress/t.target,
      label=taskUi.progress(t)}
    children[#children+1]=builtin.Button{meta={class="spy-growth-order-entry",enabled=not locked},
      content=box(taskChildren,"spy-growth-order"),
      onClick=function()taskUi.open(param,f,t,t.tier or 1,read,function(position)
        local current=read(param.entityId)
        if current and current.factory and current.factory.task and
          taskUi.sameTask(current.factory.task,t,true) then
          actionPositions[f.id]=position
          askConfirmation(param,current.factory,{action="cancel",label=_("growth_confirm_cancel")})
        end
      end)end}
  else
    local revision=f.revision
    if not f.firstStandardUsed and f.candidates and f.candidates[1] then
      children[#children+1]=text(_("growth_first_standard_hint"),"spy-growth-task-hint")
    end
    for tier,c in ipairs(f.candidates or {}) do
      children[#children+1]=builtin.Button{meta={class="spy-growth-order-entry",enabled=not locked},
        content=box({tableRow({text(taskUi.listTitle(c,tier),"spy-growth-task-tier"),
            text(api.util.formatMoney(c.cost),"spy-growth-task-cost"),
            text(taskUi.rewardShort(c),"spy-growth-task-reward")},{1,-1,-1}),
          text(taskUi.goal(c,param.entityId),"spy-growth-task-goal")},"spy-growth-order"),
        onClick=function()taskUi.open(param,f,c,tier,read,function(position)
          actionPositions[f.id]=position
          send(param.entityId,"accept",{tier=tier,revision=revision})
        end)end}
    end
  end
  end
  return builtin.BoxLayout{children={card.ContentCard{meta={localKey="spyIndustryGrowth"},title=_("growth_title"),
    initialCalloutTextPermanent="",hasPermanentFocusables=true,gameCtx=param.gameCtx,showOnRightSide=param.showCalloutOnRightSide,
    extraChildrenPermanent={box(children,"spy-growth-root")}}}}
end)
local M={Panel=panel}
function M.pollFailures()
  if not watchedGameCtx then return end
  local id=api.engine.system.gameScriptSystem.getEntityForGameScript("spy_industry_evolution::/growth.gs")
  local c=id and id>=0 and api.engine.getComponent(id,CT.GAME_SCRIPT)
  local s=c and (c.state_native and c.state_native:asTable() or c.state)
  if not s or not s.factories then return end
  for factoryId in pairs(watchedFactories) do
    local f=s.factories[factoryId]
    if f and f.upgradeFailure and not f.upgradeFailure.seen then
      -- A panel may have closed while its native rebuild was in progress.
      pcall(showUpgradeFailure,{entityId=f.entity,gameCtx=watchedGameCtx},f)
    end
    if f and f.error then pcall(showActionError,{entityId=f.entity,gameCtx=watchedGameCtx},f) end
  end
end
M.confirmCancel=function(param,f)
  askConfirmation(param,f,{action="cancel",label=_("growth_confirm_cancel")})
end
function data() return M end
return M
