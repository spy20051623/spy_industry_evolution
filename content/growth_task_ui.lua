local react=ug_require("::/gui/main/react.lua")
local builtin=ug_require("::/gui/main/builtin.lua")
local engine=ug_require("::/gui/main/engine_react_util.tl")
local card=ug_require("::/gui/main/content_card.tl")
local lang=ug_require("::/scripts/lang_util.tl")
local M={}
function M.listTitle(task,tier)
  return string.format(_("growth_task_list_title"),_("growth_tier_"..(tier or task.tier or 1)),_("growth_task_"..task.kind))
end
function M.factoryName(entity)
  return api.engine.util.getEntityName(entity) or _("Unnamed Industry")
end
function M.goal(task,entity,name)
  name=name or M.factoryName(entity)
  local target=lang.formatInt(task.target)
  -- Workers count arrivals, not distinct people; cargo counts eligible units
  -- across all matching types, rather than requiring each type separately.
  if task.kind=="workers" then return string.format(_("growth_goal_workers"),name,target) end
  if task.kind=="supply" then return string.format(_("growth_goal_supply"),name,target) end
  if task.kind=="boost" then return string.format(_("growth_goal_boost"),name,target) end
  return string.format(_("growth_goal_products"),name,target)
end
function M.progress(task)
  return string.format(_("growth_task_progress"),lang.formatInt(task.progress or 0),lang.formatInt(task.target))
end
function M.rewardShort(task)
  return string.format(_("growth_task_reward_short"),lang.formatInt(task.reward))
end
function M.completion(task,name)
  return string.format(_("growth_task_completion"),name,lang.formatInt(task.reward))
end
function M.description(task,entity,name,status)
  name=name or M.factoryName(entity)
  return string.format(_("growth_task_description_"..status),name,_("growth_task_"..task.kind))
end
function M.sameTask(current,opened,active)
  if not current or not opened then return false end
  if active and (current.uid or opened.uid) then
    return current.uid~=nil and current.uid==opened.uid
  end
  return current.kind==opened.kind and current.target==opened.target and
    current.reward==opened.reward and current.cost==opened.cost
end
local function text(s,class) return builtin.TextView{text=s,meta={class="font-scale-body"..(class and ", "..class or "")}} end
local function line(path,s,class)
  return builtin.Component{layout=builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
    builtin.ImageView{path=path,meta={class="label"},
      scaling=builtin.type.ImageViewScaling.AutoFit},text(s,class)}}}
end
local function section(title,children)
  return card.ContentCard{title=title,extraChildrenPermanent=children}
end
-- Use the same eligible cargo set as the simulation counter. Multi-input
-- contracts share one total target, as in native supply subsidies.
function M.cargoTypes(kind,entity,legacySupply)
  local CT=api.type.ComponentType
  local ind=api.engine.getComponent(entity,CT.INDUSTRY)
  local stock=ind and api.engine.getComponent(ind.stockList,CT.STOCK_LIST)
  local eligible={}
  if stock then for _,rule in ipairs(stock.rules) do
    if (kind=="supply" and (legacySupply or not rule.booster)) or (kind=="boost" and rule.booster) then
      for _,opt in ipairs(rule.input) do for idx,n in pairs(opt) do
        if n>0 and stock.stocks[idx] then eligible[stock.stocks[idx].cargoType]=true end
      end end
    elseif kind=="products" and not rule.booster then
      for cargo,n in pairs(rule.output) do if n>0 then eligible[cargo]=true end end
    end
  end end
  local result={};for id in pairs(eligible) do result[#result+1]=id end
  table.sort(result)
  return result
end
function M.noCargoTypes(task,entity)
  return task.kind~="workers" and
    #M.cargoTypes(task.kind,entity,task.kind=="supply" and not task.factor)==0
end
local function cargoRow(task,entity,dynamic)
  local children={builtin.ImageView{path=task.kind=="workers" and
    "::/gui/construction/menu/symbol_person.tga" or "::/gui/construction/menu/filter_categories/cargo.tga",
    meta={class="label"},scaling=builtin.type.ImageViewScaling.AutoFit}}
  local types=task.kind=="workers" and {api.res.cargoTypeRep.getPassengerCargoTypeId()} or
    (dynamic and M.cargoTypes(task.kind,entity,task.kind=="supply" and not task.factor)) or
    task.cargoTypes or M.cargoTypes(task.kind,entity,task.kind=="supply" and not task.factor)
  for index,id in ipairs(types) do
    local cargo=api.res.cargoTypeRep.get(id)
    children[#children+1]=builtin.ImageView{path=cargo.icon,
      meta={class="cargo-to-deliver",tooltip=cargo.name},scaling=builtin.type.ImageViewScaling.AutoFit}
  end
  children[#children+1]=builtin.TextView{text=lang.formatInt(task.target),
    meta={class="font-scale-body, cargo-to-deliver-count"}}
  return builtin.Component{layout=builtin.BoxLayout{
    orientation=builtin.type.Orientation.Horizontal,children=children}}
end
local function locationRow(task,entity,name)
  local direction=task.kind=="products" and "From" or "To"
  return builtin.Component{layout=builtin.BoxLayout{
    orientation=builtin.type.Orientation.Horizontal,children={
      builtin.Button{meta={class="label",tooltip=_(direction)},
        content=builtin.ImageView{path="::/gui/builtin/window/icons/symbol_locate.tga",
          scaling=builtin.type.ImageViewScaling.AutoFit},
        onClick=function()api.gui.camera.focusEntity(entity)end},
      builtin.Button{content=text(name),onClick=function()
        react.fireEvent(nil,"selectEntity",{entity=entity,stack=true})
      end}
    }}}
end
-- Rendering hierarchy follows subventions_gui.tl. Separate recipes preserve
-- the native stylesheet's direct-child selectors; Component stand-ins do not.
local Condition=react.RegisterRecipe("SpyGrowthTaskCondition",function(p)
  return builtin.BoxLayout{child=builtin.Component{meta={class="card"},layout=builtin.BoxLayout{
    orientation=builtin.type.Orientation.Vertical,children={line(p.icon,p.text,"list-text")}}}}
end)
local Action=react.RegisterRecipe("SpyGrowthTaskAction",function(p)
  local confirmRef=p.confirmRef
  if p.completed then
    return builtin.BoxLayout{children={builtin.ImageView{
      meta={class="subsidy-completed"},
      path="::/game_mechanics/subventions/icons/mark_complete.tga",
      scaling=builtin.type.ImageViewScaling.AutoFit}}}
  end
  local function button(label,icon,fn,class,ref,enabled)
    local props={meta={class=class,enabled=enabled},onClick=fn,
      content=icon and builtin.Component{layout=builtin.BoxLayout{
        orientation=builtin.type.Orientation.Horizontal,children={
          builtin.ImageView{path=icon,scaling=builtin.type.ImageViewScaling.AutoFit},text(label)}}} or text(label)}
    return ref and builtin.Button(react.ref(ref),props) or builtin.Button(props)
  end
  local children={}
  if p.active then children[#children+1]=builtin.ProgressBar{meta={class="font-scale-annotation"},
      value=p.task.progress/p.task.target,
      label=M.progress(p.task)} end
  children[#children+1]=builtin.BoxLayout{meta={class="task-action-buttons"},
    orientation=builtin.type.Orientation.Horizontal,children={
      button(_("growth_task_back_button"),"::/gui/menu/icons/back.tga",p.onClose,"secondary",p.backRef,true),
      not p.readOnly and button(_(p.active and "growth_cancel" or "growth_task_accept_button"),
        p.active and "::/game_mechanics/subventions/icons/subsidy_decline.tga" or
          "::/game_mechanics/subventions/icons/subsidy_acceptance.tga",
        function()
          local ok,pos=pcall(function()return confirmRef:get():getPosition(1.0,0.0)end)
          p.onClose();p.onConfirm(ok and pos or nil)
        end,"primary",confirmRef,p.enabled) or nil}}
  return builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children=children}
end)
local TaskCard=react.RegisterRecipe("SpyGrowthTaskCard",function(p)
  local confirmRef=react.useNodeRef()
  local backRef=react.useNodeRef()
  -- Match the native subsidy card's mount-time focus, without selecting the
  -- destructive action in an active task or stealing focus on progress updates.
  react.onMount(function()
    if p.completed or api.util.getInputMode()~=api.type["enum"].InputMode.Gamepad then return end
    local ref=not p.active and not p.readOnly and p.enabled~=false and confirmRef or backRef
    local node=ref:get()
    if node then node:focus() end
  end)
  local t=p.task
  local rows={cargoRow(t,p.entityId,not p.readOnly),locationRow(t,p.entityId,p.name),
    line("::/game_mechanics/subventions/icons/symbol_calendar.tga",_("growth_task_unlimited"))}
  if p.active and M.noCargoTypes(t,p.entityId) then
    rows[#rows+1]=text(_("growth_task_no_cargo"))
  end
  if p.readOnly and not p.completed then rows[#rows+1]=builtin.ProgressBar{value=t.progress/t.target,
    label=M.progress(t)} end
  local status=p.completed and "completed" or p.readOnly and "ended" or p.active and "active" or "candidate"
  local mainChildren={
    section(nil,{text(M.description(t,p.entityId,p.name,status),"card, description")}),
    section(_("growth_task_section"),{builtin.Component{layout=builtin.BoxLayout{
      meta={class="task-box"},orientation=builtin.type.Orientation.Vertical,children=rows}}}),
    section(_("growth_task_acceptance_section"),{Condition{
      icon="::/game_mechanics/finance/icons/symbol_hand_dollar.tga",
      text=string.format(_((p.active or p.readOnly) and "growth_task_paid" or "growth_task_payment"),api.util.formatMoney(t.cost))}}),
    section(_("growth_task_fulfillment_section"),{Condition{
      icon="::/game_mechanics/subventions/icons/completion.tga",
      text=M.completion(t,p.name)}})}
  return builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={
    builtin.Component{meta={class="card-area"},layout=builtin.BoxLayout{
      orientation=builtin.type.Orientation.Vertical,children=mainChildren}},
    Action{task=t,active=p.active,readOnly=p.readOnly,completed=p.completed,
      enabled=p.enabled,onClose=p.onClose,onConfirm=p.onConfirm,confirmRef=confirmRef,backRef=backRef}}}
end)
local WindowContent=react.RegisterRecipe("SpyGrowthTaskWindowContent",function(p)
  return builtin.BoxLayout{children={TaskCard(p)}}
end)
local EntityContent=react.RegisterRecipe("SpyGrowthTaskEntityContent",function(p)
  react.useInputAction("IA_NAV_LEFT",react.iaFocusTraversal(true,false))
  react.useInputAction("IA_NAV_RIGHT",react.iaFocusTraversal(true,true))
  react.useInputAction("IA_NAV_UP",react.iaFocusTraversal(false,false))
  react.useInputAction("IA_NAV_DOWN",react.iaFocusTraversal(false,true))
  return builtin.BoxLayout{children={p.content}}
end)
local function windowApi(param) return param.gameCtx.windowContainer:get():getApi() end
local Window
Window=react.RegisterWrapperRecipe("SpyGrowthTaskWindow",builtin.Window,function(p)
  local current=engine.useStepState(function()return p.read(p.entityId) or {} end):old()
  local f=current and current.factory
  local task
  if f then
    if p.active then task=f.task
    elseif not f.task and f.candidates then task=f.candidates[p.tier] end
  end
  local valid=M.sameTask(task,p.task,p.active) and api.engine.entityExists(p.entityId) and
    api.engine.getComponent(p.entityId,api.type.ComponentType.INDUSTRY)~=nil and
    (p.active or f.revision==p.revision)
  react.onStep(function()if not valid then p.onClose() end end)
  local pinned=react.useState(false)
  local inputMode=engine.useStepState(function()return api.util.getInputMode()end):old()
  local gamepad=inputMode==api.type["enum"].InputMode.Gamepad
  local console=api.util.isConsoleMode()
  react.useInputAction("IA_MENU_BACK",react.iaHandler(p.onClose))
  local window={title=string.format(_("growth_task_detail_title"),_("growth_tier_"..p.tier)),
    meta={class="entity-window, spy-growth-task-window"},onClose=p.onClose,
    autoFocusOnBecomingVisible=gamepad,
    content=EntityContent{meta=gamepad and {forceFocusable=true} or nil,
      content=WindowContent{entityId=p.entityId,name=M.factoryName(p.entityId),
        task=task or p.task,active=p.active,enabled=not not (valid and not f.busy),
        onClose=p.onClose,onConfirm=p.onConfirm}}}
  -- Platform compatibility only controls optional Window fields. Focus and
  -- Back navigation follow the input device, including PC gamepads.
  if not console then
    window.closable=true
    window.movable=true
    window.initialX=1
    window.initialY=0
    window.autoVisibilityOnFocusChange=false
    window.locateVisible=false
    window.pinnable=inputMode==api.type["enum"].InputMode.KeyboardMouse
    window.pinned=pinned:old()
    window.onPinned=function(v)pinned:set(v)end
    window.onMovedChange=function()pinned:set(true)end
  end
  return builtin.Window(window)
end)
M.Window=Window
M.NotificationContent=WindowContent
function M.close(param) windowApi(param).removeAllWindows(Window) end
function M.open(param,f,task,tier,read,onConfirm)
  local wc=windowApi(param)
  local snapshot={};for key,value in pairs(task) do snapshot[key]=value end
  wc.addSingletonWindow(Window,{gameCtx=param.gameCtx,entityId=param.entityId,task=snapshot,
    tier=tier,active=f.task~=nil,revision=f.revision,read=read,onConfirm=onConfirm,
    onClose=function()M.close(param)end})
end
return M
