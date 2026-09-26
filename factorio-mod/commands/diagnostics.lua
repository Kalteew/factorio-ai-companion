local u = require("commands.init")

local M = {}

local function position(value)
  return value and {x = value.x, y = value.y} or nil
end

local function nearest_entity(surface, center, radius)
  local closest, distance = nil, math.huge
  for _, entity in ipairs(surface.find_entities_filtered{position = center, radius = radius}) do
    if entity.valid and entity.type ~= "character" and entity.type ~= "resource"
      and entity.type ~= "tree" and entity.type ~= "corpse" then
      local dx = entity.position.x - center.x
      local dy = entity.position.y - center.y
      local d = dx * dx + dy * dy
      if d < distance then closest, distance = entity, d end
    end
  end
  return closest
end

local function fluid_snapshot(entity)
  local result = {}
  local ok, contents = pcall(function() return entity.get_fluid_contents() end)
  if ok and contents then result.contents = contents end
  local boxes = {}
  local ok_count, raw_count = pcall(function() return entity.fluids_count end)
  local count = ok_count and (tonumber(raw_count) or 0) or 0
  for index = 1, count do
    local box = {}
    local ok_fluid, fluid = pcall(function() return entity.get_fluid(index) end)
    if ok_fluid and fluid then box.fluid = fluid end
    local ok_capacity, capacity = pcall(function() return entity.get_fluid_capacity(index) end)
    if ok_capacity then box.capacity = capacity end
    local ok_segment, segment = pcall(function() return entity.get_fluid_segment_id(index) end)
    if ok_segment then box.segment_id = segment end
    boxes[index] = box
  end
  if next(boxes) then result.boxes = boxes end
  return next(result) and result or nil
end

local function signal_snapshot(signal)
  if not signal then return nil end
  local result = {count = signal.count}
  if signal.signal then
    result.signal = {
      type = signal.signal.type,
      name = signal.signal.name,
      quality = signal.signal.quality,
    }
  end
  return result
end

local function circuit_snapshot(entity, connector_id, wire_name)
  local ok, network = pcall(function() return entity.get_circuit_network(connector_id) end)
  if not ok or not network then return nil end
  local result = {
    wire = wire_name,
    network_id = network.network_id,
    connected_circuit_count = network.connected_circuit_count,
    signals = {},
  }
  for _, signal in ipairs(network.signals or {}) do
    result.signals[#result.signals + 1] = signal_snapshot(signal)
  end
  return result
end

local function circuits(entity)
  local result = {}
  -- Factorio 2.x uses wire connector IDs. Keep a wire_type fallback for older 2.0
  -- builds so the diagnostic remains useful across the supported 2.0 line.
  local ids = defines.wire_connector_id or {}
  local wires = {
    {name = "red", id = ids.circuit_red},
    {name = "green", id = ids.circuit_green},
  }
  for _, wire in ipairs(wires) do
    if wire.id ~= nil then
      local snapshot = circuit_snapshot(entity, wire.id, wire.name)
      if snapshot then result[wire.name] = snapshot end
    end
  end
  if next(result) == nil and defines.wire_type then
    for _, wire in ipairs({{name = "red", id = defines.wire_type.red}, {name = "green", id = defines.wire_type.green}}) do
      if wire.id ~= nil then
        local snapshot = circuit_snapshot(entity, wire.id, wire.name)
        if snapshot then result[wire.name] = snapshot end
      end
    end
  end
  return next(result) and result or nil
end

local function logistic_filter(filter)
  if not filter then return nil end
  local result = {min = filter.min, max = filter.max, minimum_delivery_count = filter.minimum_delivery_count}
  if filter.value then
    result.value = {
      type = filter.value.type,
      name = filter.value.name,
      quality = filter.value.quality,
      comparator = filter.value.comparator,
    }
  end
  return result
end

local function logistic_section(section)
  local result = {
    index = section.index,
    type = section.type,
    is_manual = section.is_manual,
    active = section.active,
    multiplier = section.multiplier,
    filters = {},
  }
  for index, filter in ipairs(section.filters or {}) do
    result.filters[index] = logistic_filter(filter)
  end
  return result
end

local function logistic_snapshot(entity)
  local result = {}
  local ok, points = pcall(function() return entity.get_logistic_point() end)
  if not ok or not points then return nil end
  if points.owner then points = {points} end
  for index, point in ipairs(points) do
    if point and point.valid then
      local point_result = {
        index = index,
        mode = point.mode,
        exact = point.exact,
        enabled = point.enabled,
        sections = {},
        targeted_items_pickup = point.targeted_items_pickup,
        targeted_items_deliver = point.targeted_items_deliver,
      }
      for section_index, section in ipairs(point.sections or {}) do
        point_result.sections[section_index] = logistic_section(section)
      end
      result[#result + 1] = point_result
    end
  end
  return #result > 0 and result or nil
end

local function electric_snapshot(entity)
  local result = {}
  local ok_id, network_id = pcall(function() return entity.electric_network_id end)
  if ok_id and network_id then result.network_id = network_id end
  local ok_stats, stats = pcall(function() return entity.electric_network_statistics end)
  if ok_stats and stats then
    result.input = stats.input_counts or {}
    result.output = stats.output_counts or {}
    result.storage = stats.storage_counts or {}
  end
  return next(result) and result or nil
end

local function control_snapshot(entity)
  local ok, behavior = pcall(function() return entity.get_control_behavior() end)
  if not ok or not behavior then return nil end
  local result = {}
  for _, field in ipairs({
    "type", "connect_to_logistic_network", "read_contents", "read_stopped_train",
    "read_logistics", "circuit_condition", "logistic_condition", "enabled",
    "circuit_enable_disable", "connect_to_logistic_network",
  }) do
    local ok_field, value = pcall(function() return behavior[field] end)
    if ok_field and value ~= nil then result[field] = value end
  end
  return next(result) and result or nil
end

u.register("entity_diagnostics", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local x, y = tonumber(args.x), tonumber(args.y)
    if not x or not y then u.reject("Invalid coordinates") end
    local radius = math.min(16, math.max(0.5, tonumber(args.radius) or 2))
    local entity = nearest_entity(companion.entity.surface, {x = x, y = y}, radius)
    if not entity then u.json_response({id = id, error = "No entity"}); return end
    local result = {
      id = id,
      entity = {name = entity.name, type = entity.type, position = position(entity.position), unit_number = entity.unit_number},
    }
    if args.includeFluid then result.fluid = fluid_snapshot(entity) end
    if args.includeCircuits then result.circuits = circuits(entity) end
    if args.includeLogistics then result.logistics = logistic_snapshot(entity) end
    if args.includeElectric then result.electric = electric_snapshot(entity) end
    if args.includeControl then result.control = control_snapshot(entity) end
    u.json_response(result)
  end)
end)

return M
