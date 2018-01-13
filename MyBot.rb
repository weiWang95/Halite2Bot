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
game = Game.new("newVersion")
# We print our start message to the logs
game.logger.info("Starting my Opportunity bot!")

MyLog = game.logger

while true
  # TURN START
  # Update the map for the new turn and get the latest version
  game.update_map
  map = game.map
  me = map.me

  # Here we define the set of commands to be sent to the Halite engine at the
  # end of the turn
  command_queue = []

  # check own planet safety
  if map.enemy_haste?
    enemy_ships = map.enemy_ships
    if me.ships.all?(&:undocked?)
      me.ships.each do |ship|
        command_queue << ship.want_attack_enemy(map, enemy_ships.first)
      end
    else
      docked_ships = me.docked_ships
      ship = if docked_ships.present?
               command_queue += docked_ships.map(&:undock)
               docked_ships.sample
             else
               me.ships.sample
             end
      position = Position.new(ship.x, ship.y)
      me.idle_ships.each do |ship|
        command_queue << ship.aggregate(position, map)
      end
    end
  end

  # planet defence
  map.own_planets.each do |planet|
    enemy_ships = map.dangerous_enemy_ships(planet)
    next if enemy_ships.blank?

    defence_ships = map.can_defence_ships(planet)
    if defence_ships.present?
      defence_ships[0, enemy_ships.size].each do |ship|
        command_queue << ship.want_attack_enemy(map, enemy_ships.first)
      end
      next
    end
  end

  # For each idle ship we control
  me.idle_ships.each do |ship|

    unowned_planet = map.nearest_unowned_planet(ship)
    if unowned_planet && ship.calculate_distance_between(unowned_planet) <= Game::Constants::MAX_ALLOW_WANT_DOCK_DISTANCE
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
