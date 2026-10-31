local react=ug_require("::/gui/main/react.lua")
local builtin=ug_require("::/gui/main/builtin.lua")
local engine=ug_require("::/gui/main/engine_react_util.tl")
local cargoUi=ug_require("::/gui/main/cargo_react_util.tl")
local cargoUtil=ug_require("::/gui/main/cargo_util.tl")
local colorUtil=ug_require("::/gui/main/color_util.tl")
local entityUtil=ug_require("::/scripts/entity_util.tl")
local hudUtil=ug_require("::/gui/hud/hud_react_util.tl")
local selector=ug_require("::/gui/main/selector_react_util.tl")
local CT=api.type.ComponentType
local M={}

local function cargoData(hud,entity,direction,cargo)
  local entry=hud[entity]
  if not entry then entry={inputs={},outputs={}};hud[entity]=entry end
  local list=entry[direction]
  for _,item in ipairs(list)do if item.cargoType==cargo then return end end
  list[#list+1]={cargoType=cargo}
end

function M.build(entity,task)
  local industry=api.engine.getComponent(entity,CT.INDUSTRY)
  if not industry then return {hud={},flows={}} end
  local targetPos=entityUtil.getPosition(entity)
  if not targetPos then return {hud={},flows={}} end
  local relevant={}
  for _,cargo in ipairs(task.cargoTypes or {})do relevant[cargo]=true end
  local passenger=api.res.cargoTypeRep.getPassengerCargoTypeId()
  if task.kind=="workers" then relevant[passenger]=true end
  local hud,flows={},{}
  local isProduct=task.kind=="products"
  local colors=api.gui.genericRep.findAndGet("::/gui/layers/layer_colors.gres").data
  local transparency=api.gui.genericRep.findAndGet("::/gui/main/transparency.gres").data
  local palette=isProduct and colors.CargoFlow.Consumers3D or colors.CargoFlow.Suppliers3D
  local actual=colorUtil.toArray4(palette.Actual)
  local potential=colorUtil.toArray4WithTransparency(palette.Potential,transparency.VeryLow)
  for cargo in pairs(relevant)do cargoData(hud,entity,isProduct and "outputs" or "inputs",cargo) end
  local function add(other,cargo,town,forceActual)
    if other==entity then return end
    local otherPos=entityUtil.getPosition(other)
    if not otherPos then return end
    local count=forceActual and 1 or (isProduct and
      cargoUtil.getCargoFlowCount(entity,other,cargo,town) or
      cargoUtil.getCargoFlowCount(other,entity,cargo,town))
    local flow=api.type.LayerConfig.CargoFlowRenderableConfig.FlowData.new()
    flow.from=isProduct and targetPos or otherPos
    flow.to=isProduct and otherPos or targetPos
    flow.speed=count>0 and 40.0 or 0.0
    flow.arrowColors=count>0 and actual or potential
    flow.cargoIconAlpha=count>0 and 1.0 or 0.6
    flow.cargoTypes={cargo}
    flows[#flows+1]=flow
    cargoData(hud,other,isProduct and "inputs" or "outputs",cargo)
  end
  if task.kind=="workers" then
    local towns={}
    api.engine.forEachEntityWithComponent(function(town)
      local position=entityUtil.getPosition(town)
      if position then towns[#towns+1]={entity=town,position=position} end
    end,CT.TOWN)
    table.sort(towns,function(a,b)
      return api.type.Vec3f.distance2(a.position,targetPos)<api.type.Vec3f.distance2(b.position,targetPos)
    end)
    for i=1,math.min(#towns,5)do add(towns[i].entity,passenger,true,true) end
  else
    local neededStockType=api.type["enum"].StockListType[isProduct and "InputStock" or "OutputStock"]
    api.engine.forEachEntityWithComponent(function(other)
      if other~=entity then
        local otherIndustry=api.engine.getComponent(other,CT.INDUSTRY)
        local stock=otherIndustry and api.engine.getComponent(otherIndustry.stockList,CT.STOCK_LIST)
        local found={}
        for _,item in ipairs(stock and stock.stocks or {})do
          if item.type==neededStockType and relevant[item.cargoType] and not found[item.cargoType] then
            found[item.cargoType]=true
            add(other,item.cargoType,false,false)
          end
        end
      end
    end,CT.INDUSTRY)
    if isProduct then
      local towns=api.engine.system.townBuildingSystem
      if towns then for town in pairs(towns.getTown2BuildingMap())do
        for cargo,limit in pairs(towns.getCargoSupplyAndLimit(town))do
          if relevant[cargo] and limit[2]>0 then add(town,cargo,true,false) end
        end
      end end
    end
  end
  local layer
  if #flows>0 then
    layer=api.type.LayerConfig.new()
    local config=api.type.LayerConfig.CargoFlowRenderableConfig.new()
    config.flowData=flows
    layer.cargoFlowRenderableConfig=config
  end
  return {hud=hud,flows=flows,layer=layer}
end

M.HudMaster=react.RegisterRecipe("SpyGrowthTaskHudMaster",function(param,userParam)
  react.setMouseTransparent(true)
  local data=engine.useStepStateTimer(function()return userParam.hud[param.entity]end):old()
  if not data then return nil end
  return builtin.BoxLayout{children={cargoUi.CargoInputOutputIndicator{data=data}}}
end)

function M.action(ctx,entity,task)
  local map=engine.useStepState(function()return M.build(entity,task)end):old()
  if not map then return nil end
  local selected=react.useRef(-1)
  local hudParam=react.useRef({hud=map.hud}):get()
  hudParam.hud=map.hud
  local hudConfig=api.gui.genericRep.findAndGet("::/gui/hud/hud_gui_config.gres").data
  local finance=api.gui.genericRep.findAndGet("::/game_mechanics/finance/sound/finance_sfx.gres").data
  local children={builtin.HudIconManagerConfig{
    masterRecipe=M.HudMaster,userParam=hudParam,
    preFilter={CT.TOWN,CT.INDUSTRY},
    localKey="spy-growth-task-"..tostring(task.uid).."-"..tostring(entity),
    showCosts=true,showIncome=true,incomeSFX=finance.Income or {},
    costsRenderDistance=hudConfig.renderDistances.Costs,
    visibilityThresholds=hudUtil.makeDefaultVisibilityThresholds(),
    vehicleIconOffsets=hudUtil.makeVehicleIconOffsets(hudConfig.vehicleIconOffsets)}}
  local mouseSelector=selector.makeDefaultSelectorIfMouse(ctx.rendererComponent,selected)
  if mouseSelector then children[#children+1]=mouseSelector end
  local tooltips=selector.makeDefaultSelectorTooltipsIfMouse(selected)
  if tooltips then children[#children+1]=tooltips end
  if map.layer then children[#children+1]=builtin.LayerConfig{config=map.layer} end
  return builtin.ActionDescriptor{tool="spy-growth-task",horizontalPromptList=true,
    highlightedEntities={entity},terrainCirclePolicy="Never",children=children}
end

return M
