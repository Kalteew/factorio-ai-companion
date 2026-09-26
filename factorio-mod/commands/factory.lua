local u = require("commands.init")

local function stat_summary(stats)
  if not stats then return nil end
  local ok, result = pcall(function()
    return {
      input = stats.input_counts or {},
      output = stats.output_counts or {},
      storage = stats.storage_counts or {},
    }
  end)
  return ok and result or nil
end

local function array_length(value)
  if not value then return 0 end
  local ok, result = pcall(function() return #value end)
  return ok and result or 0
end

local function logistic_summary(network, include_contents)
  local result = {
    id = network.network_id,
    name = network.custom_name,
    logistic_robots = {
      available = network.available_logistic_robots,
      total = network.all_logistic_robots,
    },
    construction_robots = {
      available = network.available_construction_robots,
      total = network.all_construction_robots,
    },
    members = {
      providers = array_length(network.providers),
      requesters = array_length(network.requesters),
      storages = array_length(network.storages),
      other = array_length(network.logistic_members),
    },
  }
  if include_contents then
    local ok, contents = pcall(function() return network.get_contents() end)
    if ok then result.contents = contents end
  end
  return result
end

local function surface_and_force(args)
  local cid = tonumber(args.companionId) or 0
  local companion = cid > 0 and u.get_companion(cid) or nil
  if cid > 0 and not companion then u.not_found(cid); return end
  local player = game.connected_players[1] or game.players[1]
  local surface = args.surface and game.surfaces[args.surface]
    or (companion and companion.entity.surface)
    or (player and player.surface)
    or game.surfaces[1]
  if not surface then u.reject("Surface not found") end
  local force = (companion and companion.entity.force) or (player and player.force) or game.forces.player
  return surface, force
end

local function entity_counts(surface, force)
  local result = {}
  local types = {
    "assembling-machine", "furnace", "mining-drill", "transport-belt", "inserter",
    "container", "logistic-container", "electric-pole", "train-stop", "locomotive",
    "cargo-wagon", "fluid-wagon", "roboport", "turret",
  }
  for _, entity_type in ipairs(types) do
    local ok, count = pcall(function()
      return surface.count_entities_filtered{force = force, type = entity_type}
    end)
    if ok then result[entity_type] = count end
  end
  return result
end

u.register("factory_snapshot", function(args)
  u.safe_command(function()
    local surface, force = surface_and_force(args)
    if not surface then return end
    local result = {
      surface = surface.name,
      force = force.name,
      tick = game.tick,
      time_seconds = game.tick / 60,
      daytime = surface.daytime,
      darkness = surface.darkness,
      pollution = {
        total = surface.get_total_pollution(),
        at_spawn = surface.get_pollution(force.get_spawn_position(surface)),
      },
      map = {
        resources = surface.get_resource_counts(),
        has_global_electric_network = surface.has_global_electric_network,
      },
      research = force.current_research and {
        name = force.current_research.name,
        progress = force.research_progress,
      } or nil,
      players = #force.players,
      rockets_launched = force.rockets_launched,
    logistics = {networks = {}, network_count = 0},
      production = {},
    }

    local ok, networks = pcall(function() return force.logistic_networks[surface.name] end)
    if ok and networks then
      for _, network in ipairs(networks) do
        result.logistics.network_count = result.logistics.network_count + 1
        result.logistics.networks[tostring(network.network_id)] = logistic_summary(
          network, args.includeLogisticsContents)
      end
    end

    local item_stats = force.get_item_production_statistics(surface)
    local fluid_stats = force.get_fluid_production_statistics(surface)
    result.production.items = stat_summary(item_stats)
    result.production.fluids = stat_summary(fluid_stats)

    local ok_power, power_stats = pcall(function() return surface.global_electric_network_statistics end)
    if ok_power and power_stats then result.power = stat_summary(power_stats) end

    local ok_pollution, pollution_stats = pcall(function() return surface.pollution_statistics end)
    if ok_pollution and pollution_stats then result.pollution.statistics = stat_summary(pollution_stats) end

    if args.includeEntities then result.entities = entity_counts(surface, force) end
    u.json_response(result)
  end)
end)

return {}
