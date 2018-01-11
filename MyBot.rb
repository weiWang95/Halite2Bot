# Welcome to your first Halite-II bot!
#
# This bot's name is Opportunity. It's purpose is simple (don't expect it to win
# complex games :) ):
#  1. Initialize game
#  2. If a ship is not docked and there are unowned planets
#   a. Try to Dock in the planet if close enough
#   b. If not, go towards the planet

# Load the files we need
$:.unshift(File.dirname(__FILE__) + "/hlt")
require 'game'

# GAME START

# Here we define the bot's name as Opportunity and initialize the game, including
# communication with the Halite engine.
game = Game.new("Opportunity")
# We print our start message to the logs
game.logger.info("Starting my Opportunity bot!")

MyLog = game.logger

module NumericalValue
  MAX_ALLOW_WANT_DOCK_DISTANCE = 50
end

while true
  # TURN START
  # Update the map for the new turn and get the latest version
  game.update_map
  map = game.map

  # Here we define the set of commands to be sent to the Halite engine at the
  # end of the turn
  command_queue = []

  # For each ship we control
  map.me.ships.each do |ship|
    # if the ship is docked
    next unless ship.undocked?

    unowned_planet = map.nearest_unowned_planet(ship)
    if unowned_planet && ship.calculate_distance_between(unowned_planet) <= NumericalValue::MAX_ALLOW_WANT_DOCK_DISTANCE
      command_queue << ship.want_dock_planet(map, unowned_planet)
      next
    end

    unfulled_planet = map.nearest_own_unfull_planet(ship)
    if unfulled_planet
      command_queue << ship.want_dock_planet(map, unfulled_planet)
      next
    end

    enemy_ship = map.nearest_enemy_docked_ship(ship) || map.nearest_enemy_ship(ship)
    if enemy_ship
      command_queue << ship.want_attack_enemy(map, enemy_ship)
      next
    end
  end

  game.send_command_queue(command_queue)
end
