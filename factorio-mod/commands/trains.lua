local u = require("commands.init")

local function position(value)
  return value and {x = value.x, y = value.y} or nil
end

local function entity_ref(entity)
  if not entity or not entity.valid then return nil end
  return {name = entity.name, type = entity.type, position = position(entity.position)}
end

local function schedule_snapshot(schedule)
  if not schedule then return nil end
  local result = {current = schedule.current, records = {}}
  for index, record in ipairs(schedule.records or {}) do
    local copy = {station = record.station, rail = record.rail, temporary = record.temporary, wait_conditions = {}}
    for condition_index, condition in ipairs(record.wait_conditions or {}) do
      copy.wait_conditions[condition_index] = {
        type = condition.type,
        compare_type = condition.compare_type,
        ticks = condition.ticks,
        compare = condition.compare,
        damage = condition.damage,
        fluid_count = condition.fluid_count,
        item_count = condition.item_count,
        circuit = condition.circuit,
      }
    end
    result.records[index] = copy
  end
  return result
end

local function train_snapshot(train, include_schedule)
  local result = {
    id = train.id,
    state = train.state,
    manual_mode = train.manual_mode,
    speed = train.speed,
    weight = train.weight,
    group = train.group,
    has_path = train.has_path,
    station = entity_ref(train.station),
    path_end_stop = entity_ref(train.path_end_stop),
    front_stock = entity_ref(train.front_stock),
    back_stock = entity_ref(train.back_stock),
    carriages = {},
  }
  for index, carriage in ipairs(train.carriages or {}) do
    result.carriages[index] = entity_ref(carriage)
  end
  if include_schedule then result.schedule = schedule_snapshot(train.schedule) end
  return result
end

local function add_train(result, seen, train, include_schedule)
  if not train or not train.valid or seen[train.id] then return end
  seen[train.id] = true
  local ok, snapshot = pcall(train_snapshot, train, include_schedule)
  if ok then result[#result + 1] = snapshot end
end

u.register("train_snapshot", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local surface = companion.entity.surface
    local radius = math.min(512, math.max(8, tonumber(args.radius) or 128))
    local center = companion.entity.position
    if args.x ~= nil and args.y ~= nil then center = {x = tonumber(args.x), y = tonumber(args.y)} end
    local result, seen = {}, {}
    for _, stop in ipairs(surface.find_entities_filtered{position = center, radius = radius, type = "train-stop", force = companion.entity.force}) do
      local ok, trains = pcall(function() return stop.get_train_stop_trains() end)
      if ok then for _, train in ipairs(trains or {}) do add_train(result, seen, train, args.includeSchedule) end end
      local ok_stopped, stopped = pcall(function() return stop.get_stopped_train() end)
      if ok_stopped then add_train(result, seen, stopped, args.includeSchedule) end
    end
    for _, entity_type in ipairs({"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}) do
      for _, stock in ipairs(surface.find_entities_filtered{position = center, radius = radius, type = entity_type, force = companion.entity.force}) do
        local ok, train = pcall(function() return stock.train end)
        if ok then add_train(result, seen, train, args.includeSchedule) end
      end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    u.json_response({id = id, surface = surface.name, center = position(center), radius = radius,
      trains = result, count = #result})
  end)
end)

return {}
