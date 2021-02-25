-- Initialize lists of free characters and ghosts
script.on_init(function()
  global.free_characters = {}
  global.ghosts = {}
  -- Default teams don't trigger on_force_created
  global.free_characters[game.forces.player.index] = {}
  global.ghosts[game.forces.player.index] = {}
end)
-- Initialize lists for a new team
script.on_event(defines.events.on_force_created, function(event)
  global.free_characters[event.force.index] = {}
  global.ghosts[event.force.index] = {}
end)
-- Remove dead character from list
script.on_event(defines.events.on_entity_died, function(event)
  global.free_characters[event.entity.force.index]
    [event.entity.unit_number] = nil
end,
  -- Fire event only for character types
  {{filter = "type", type = "character"}}
)
-- Remove respawned player from ghost list
script.on_event(defines.events.on_player_respawned, function(event)
  local player = game.players[event.player_index]
  global.ghosts[player.force.index][player.index] = nil
end)


-- Offer free character to ghosts of given force, returning true if accepted,
-- otherwise false
local ghost_offer = function(force, char)
  local list = global.ghosts[force.index]

  for i, player in pairs(list) do
    player.set_controller
      {type = defines.controllers.character, character = char}
    list[i] = nil
    return true
  end
  -- No ghosts waiting
  return false
end
-- Merge character and ghost lists
script.on_event(defines.events.on_forces_merging, function(event)
  local dest_chars = global.free_characters[event.destination.index]

  -- Offer free characters to incoming ghosts
  for unit, data in pairs(dest_chars) do
    if not data.owner then
      -- Stop offering characters on the first refusal
      if not ghost_offer(event.source, data.entity) then break else
        dest_chars[unit] = nil
      end
    end
  end
  -- Merge free characters, offering incoming characters to ghosts
  for unit, data in pairs( global.free_characters[event.source.index] ) do
    if data.owner or not ghost_offer(event.destination, data.entity) then
      dest_chars[unit] = data
    end
  end
  -- Merge ghost lists
  for unit, player in pairs( global.ghosts[event.source.index] ) do
    global.ghosts[event.destination.index][unit] = player
  end

  -- Delete source lists
  global.free_characters[event.source.index] = nil
  global.ghosts[event.source.index] = nil
end)


-- Share player's personal characters from given force
local share_all = function(player, force)
  local list = global.free_characters[force.index]

  for unit, data in pairs(list) do
    if data.owner == player then
      -- Offer character to ghosts before sharing
      if ghost_offer(force, data.entity) then
        list[unit] = nil
      else
        data.owner = nil
      end
    end
  end
end
-- Share defecting player's personal characters, or handle their ghost
script.on_event(defines.events.on_player_changed_force, function(event)
  local player = game.players[event.player_index]
  local ghost_list = global.ghosts[event.force.index]
  -- Abort if force merger already took care of things
  if not ghost_list then return end

  -- Nothing to share if player is a ghost
  if ghost_list[player.index] then
    ghost_list[player.index] = nil

    -- Find a free character in new team
    local list = global.free_characters[player.force.index]
    for unit, data in pairs(list) do
      if not data.owner then
        player.set_controller
          {type = defines.controllers.character, character = char}
        list[unit] = nil

        -- Character found, abort ghost listing
        return
      end
    end

    -- No character found, so list the defector as a ghost
    global.ghosts[player.force.index][player.index] = player
  else
    share_all(player, event.force)
  end
end)
-- Share removed player's personal characters
script.on_event(defines.events.on_pre_player_removed, function(event)
  local player = game.players[event.player_index]
  local ghost_list = global.ghosts[player.force.index]

  -- Nothing to share if player is a ghost
  if ghost_list[player.index] then
    ghost_list[player.index] = nil
  else
    share_all(player, player.force)

    -- List their current character as shared
    if not ghost_offer(player.force, player.character) then
      global.free_characters[player.force.index][player.character.unit_number] =
        {entity = player.character}
    end
    -- Prevent character from being removed with the player
    player.character = nil
  end
end)


-- Add character to list according to player settings
local list_character = function(player, char)
  local list = global.free_characters[player.force.index]

  if settings.get_player_settings(player)["persistent-character-share"].value
  then
    -- Offer shared character to ghosts before listing
    if not ghost_offer(player.force, char) then
      list[char.unit_number] = {entity = char}
    end
  else
    -- Personal character
    list[char.unit_number] = {entity = char, owner = player}
  end
end
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
  local ghost_list = global.ghosts[player.force.index]

  if ghost_list[player.index] then
    ghost_list[player.index] = nil
  else
    list_character(player, player.character)
    player.character = nil
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
      {text = "Not your team!", position = other.position}
  elseif not switched then
    player.create_local_flying_text
      {text = "Not shared!", position = other.position}
  end
end)


-- Switch to any free character or become a ghost
local next_character = function(player)
  for unit, data in pairs( global.free_characters[player.force.index] ) do
    if try_switch(player, data.entity) then return end
  end
  -- No character is free, so player is now a ghost
  global.ghosts[player.force.index][player.index] = player
end
-- Switch to another character just before death
script.on_event(defines.events.on_pre_player_died, function(event)
  next_character( game.players[event.player_index] )
end)
-- Find a character when rejoining the game
script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.players[event.player_index]
  -- Ignore players stuck in a cutscene
  if player.controller_type == defines.controllers.cutscene then return end

  if not player.character then next_character(player) end

  -- Trigger respawn if player needs a character and isn't set to respawn
  if player.character or player.ticks_to_respawn then return end
  player.ticks_to_respawn = 600
end)
