local react=ug_require("::/gui/main/react.lua")
local engine=ug_require("::/gui/main/engine_react_util.tl")
local builtin=ug_require("::/gui/main/builtin.lua")
local taskUi=ug_require("spy_industry_evolution::/growth_task_ui.lua")
local router=ug_require("::/gui/entity_window/make_non_entity_window.tl")
local core=ug_require("spy_industry_evolution::/growth_core.lua")
local taskMap=ug_require("spy_industry_evolution::/growth_task_map.lua")
local M={}
local prefix="spy_growth_task_"
local function read(p)
  local CT=api.type.ComponentType
  local id=api.engine.system.gameScriptSystem.getEntityForGameScript("spy_industry_evolution::/growth.gs")
  local c=id and id>=0 and api.engine.getComponent(id,CT.GAME_SCRIPT)
  local s=c and (c.state_native and c.state_native:asTable() or c.state)
  local f=s and s.factories and s.factories[p.factoryId]
  local active=not p.completed and f and f.task and f.task.uid==p.task.uid
  local completed=p.completed or (f and f.lastCompletedTask and f.lastCompletedTask.uid==p.task.uid)
  local task=active and f.task or completed and f and f.lastCompletedTask and
    f.lastCompletedTask.uid==p.task.uid and f.lastCompletedTask or p.task
  local entity=f and f.entity or p.entity
  task=core.copy(task)
  if active then
    task.cargoTypes=taskUi.cargoTypes(task.kind,entity,task.kind=="supply" and not task.factor)
  else
    task.cargoTypes=task.cargoTypes or p.task.cargoTypes
  end
  local exists=api.engine.entityExists(entity) and api.engine.getComponent(entity,CT.INDUSTRY)~=nil
  return {factory=f,task=task,entity=entity,exists=exists,active=not not active,completed=not not completed}
end
local Content=react.RegisterRecipe("SpyGrowthTaskNotificationContent",function(p)
  local s=engine.useStepState(function()return read(p.notification)end):old()
  if not s then return builtin.BoxLayout{} end
  if p.setActionFn then
    p.setActionFn(s.exists and function()return taskMap.action(p.gameCtx,s.entity,s.task)end or nil,
      "spyGrowthTask")
  end
  -- Registered recipes must return a native layout root, not another recipe.
  return builtin.BoxLayout{children={taskUi.NotificationContent{entityId=s.entity,name=p.notification.name or taskUi.factoryName(s.entity),
    task=s.task,active=s.active,readOnly=not s.active,completed=s.completed,
    enabled=s.exists and s.factory and not s.factory.busy,onClose=p.closeFn,
    onConfirm=function()
      local current=read(p.notification)
      if current.active and current.exists then
        ug_require("spy_industry_evolution::/growth_ui.script.lua").confirmCancel(
          {entityId=current.entity,gameCtx=p.gameCtx},current.factory)
      end
    end}}}
end)
-- Use the same view-manager event as vanilla subsidy notifications.
if not router.spyGrowthTaskInstalled then
  router.spyGrowthTaskInstalled=true
  local original=router.makeNonEntityWindowContent
  router.makeNonEntityWindowContent=function(nonEntity,ctx,map,sandbox,action,close,extra)
    if nonEntity:sub(1,#prefix)~=prefix then return original(nonEntity,ctx,map,sandbox,action,close,extra) end
    return {recipe=Content,param={keyNonEntity=nonEntity,gameCtx=ctx,isMapEditor=map,isSandboxMode=sandbox,
      notification=extra,closeFn=close[1],setActionFn=action and action[1],
      setActionFn_compareProxy=action and action[2],closeFn_compareProxy=close[2],
      meta={tag="temp.view.entity.content.spyGrowthTask"}},
      fallbackTitle=string.format(_("growth_task_detail_title"),_("growth_tier_"..(extra.task.tier or 1)))}
  end
end
function M.useDataState(p)
  local s=engine.useStepStateTimer(function()return read(p)end):old()
  local title=_(s.completed and "growth_notification_completed" or s.active and
    "growth_notification_accepted" or "growth_notification_ended")
  local icon=p.task.kind=="workers" and "::/game_mechanics/subventions/deliver_workers/deliver_workers.tga" or
    "::/game_mechanics/subventions/deliver_cargo/deliver_cargo.tga"
  local function click(stack,dry)
    local current=read(p)
    if not current.exists then return false end
    if dry then return true end
    react.fireEvent(nil,"selectViewKey",{nonEntity=prefix..p.task.uid,stack=stack,extraParam=p})
    api.gui.camera.focusEntity(current.entity)
    return true
  end
  local status=s.completed and "completed" or s.active and "active" or "ended"
  return {title=title,description=taskUi.description(s.task,s.entity,p.name,status)..(s.active and
    taskUi.noCargoTypes(s.task,s.entity) and "\n".._("growth_task_no_cargo") or "")..(s.completed and
    "\n"..taskUi.completion(s.task,p.name or taskUi.factoryName(s.entity)) or ""),
    icon=icon,hudIcon=icon,lvmIcon=icon,iconExplainTooltip=title,
    progresses=s.active and {{percentage=s.task.progress/s.task.target,
      text=taskUi.progress(s.task)}} or nil,
    wouldClick=function()return click(false,true)end,onClick=function(stack)return click(stack,false)end}
end
function data()return M end
return M
