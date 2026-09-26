local u = require("commands.init")

local function train_for(id, companion)
  local ok, train = pcall(function()
    return game.train_manager.get_train_by_id(tonumber(id))
  end)
  if not ok or not train or not train.valid then return nil end
  for _, carriage in ipairs(train.carriages or {}) do
    if carriage.valid and carriage.force == companion.entity.force and carriage.surface == companion.entity.surface then
      return train
    end
  end
  return nil
end

local function wait_condition(condition)
  if not condition then return nil end
  local result = {
    type = condition.type,
    compare_type = condition.compareType or "and",
  }
  if condition.ticks ~= nil then result.ticks = tonumber(condition.ticks) end
  if condition.item or condition.fluid or condition.signal then
    local signal_type = condition.item and "item" or (condition.fluid and "fluid" or (condition.signalType or "virtual"))
    result.condition = {
      first_signal = {type = signal_type, name = condition.item or condition.fluid or condition.signal},
      comparator = condition.compare or ">=",
      constant = tonumber(condition.count) or 0,
    }
  end
  return result
end

local function schedule_record(record)
  if type(record) ~= "table" or type(record.station) ~= "string" or record.station == "" then return nil end
  local result = {station = record.station, wait_conditions = {}}
  for index, condition in ipairs(record.waitConditions or {}) do
    local converted = wait_condition(condition)
    if converted then result.wait_conditions[index] = converted end
  end
  return result
end

u.register("train_set_schedule", function(args)
  u.safe_command(function()
    local id, companion = u.find_companion(args.companionId)
    if not id then u.not_found(); return end
    local train = train_for(args.trainId, companion)
    if not train then u.json_response({id = id, error = "Train not found on this surface or force"}); return end
    if args.clear then
      train.schedule = nil
    else
      local records = {}
      for index, record in ipairs(args.records or {}) do
        local converted = schedule_record(record)
        if not converted then u.reject("Each record needs a station name") end
        records[index] = converted
      end
      if #records == 0 then u.reject("At least one schedule record is required") end
      train.schedule = {records = records, current = tonumber(args.current) or 1}
    end
    if args.manualMode ~= nil then train.manual_mode = args.manualMode end
    if args.group ~= nil then train.group = args.group end
    u.json_response({id = id, train_id = train.id, cleared = args.clear == true,
      manual_mode = train.manual_mode, group = train.group})
  end)
end)

return {}
