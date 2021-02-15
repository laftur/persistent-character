-- Initialize lists of free characters
script.on_init(function()
  global.free_characters = {}
  -- Default teams don't trigger on_force_created
  global.free_characters[game.forces.player.index] = {}
end)
-- Initialize list of free characters for a new team
script.on_event(defines.events.on_force_created, function(event)
  global.free_characters[event.force.index] = {}
end)
-- Merge free character lists
script.on_event(defines.events.on_forces_merged, function(event)
  for unit, data in pairs( global.free_characters[event.source_index] ) do
    global.free_characters[event.destination.index][unit] = data
  end
  -- Delete source list
  global.free_characters[event.source_index] = nil
end)


-- Add character to list according to player settings
local list_character = function(player, char)
  local list = global.free_characters[player.force.index]

  if settings.get_player_settings(player)["persistent-character-share"].value
  then
    -- Shared character
    list[char.unit_number] = {entity = char}
  else
    -- Personal character
    list[char.unit_number] = {entity = char, owner = player}
  end
end
-- Dissociate from character, becoming a static view of the spawn location
local detach_character = function(player)
  player.set_controller{
    type = defines.controllers.cutscene,
    start_position = player.force.get_spawn_position(player.surface)
  }
end
-- Share removed player's personal characters
script.on_event(defines.events.on_pre_player_removed, function(event)
  local player = game.players[event.player_index]
  local list = global.free_characters[player.force.index]
  -- Detach character if they had one
  if player.character then
    list_character(player, player.character)
    detach_character(player)
  end

  for unit, data in pairs(list) do
    if data.owner == player then data.owner = nil end
  end
end)
-- Remove dead character from list
script.on_event(defines.events.on_entity_died, function(event)
  global.free_characters[event.entity.force.index]
    [event.entity.unit_number] = nil
end,
  -- Fire event only for character types
  {{filter = "type", type = "character"}}
)
-- Add built character to list
script.on_event(defines.events.on_built_entity, function(event)
  list_character(game.players[event.player_index], event.created_entity)
end,
  -- Fire event only for character types
  {{filter = "type", type = "character"}}
)
-- Return character to list instead of disappearing on logout
script.on_event(defines.events.on_pre_player_left_game, function(event)
  local player = game.players[event.player_index]
  -- Detach character if they had one
  if player.character then
    list_character(player, player.character)
    detach_character(player)
  end
end)


-- Switch player's character to char
-- Return true if successful, false if char is of player's team but unshared,
-- or nil if char is of another team.
local try_switch = function(player, char)
  local list = global.free_characters[player.force.index]
  local data = list[char.unit_number]

  -- Abort if char is part of another team
  if not data then return end

  if (not data.owner) or data.owner == player then
    -- Character is shared or owned by player
    if player.character then list_character(player, player.character) end
    -- No need to detach because we're about to attach to something else

    settings.get_player_settings(player)["persistent-character-share"] =
      {value = data.owner ~= player}
    player.set_controller
      {type = defines.controllers.character, character = char}
    list[char.unit_number] = nil
    return true
  end

  -- Character is owned by another player
  return false
end
-- Explicitely switch to a selected character
script.on_event("persistent-character-switch", function(event)
  local player = game.players[event.player_index]
  local other = player.selected
  -- Abort if a character isn't selected
  if (not other) or other.type ~= "character" then return end

  local switched = try_switch(player, other)
  -- Notify player of results
  if switched == nil then
    player.create_local_flying_text
      {text = "Not your team!", postion = other.position}
  elseif not switched then
    player.create_local_flying_text
      {text = "Not shared!", postion = other.position}
  end
end)
-- Switch to any free character
local next_character = function(player)
  for unit, data in pairs( global.free_characters[player.force.index] ) do
    if try_switch(player, data.entity) then return end
  end
  -- No character is free, so trigger a respawn
  player.ticks_to_respawn = nil
end
-- Switch to another character just before death
script.on_event(defines.events.on_pre_player_died, function(event)
  next_character( game.players[event.player_index] )
end)
-- Find a character when rejoining the game
script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.players[event.player_index]
  if not player.character then next_character(player) end
end)
