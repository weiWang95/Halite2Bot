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
version_name = "V9"
game = Game.new(version_name)
# We print our start message to the logs
game.logger.info("Starting my #{version_name} bot!")

haste_strategy = false

MyLog = game.logger
while true
  begin
    # TURN START
    # Update the map for the new turn and get the latest version
    game.update_map
    map = game.map
    me = map.me

    # Here we define the set of commands to be sent to the Halite engine at the
    # end of the turn
    command_queue = []

    # check own planet safety
    if map.enemy_haste? || haste_strategy
      haste_strategy = true
      command_queue += map.defence_haste_strategy
    end

    # planet defence
    map.own_planets.each do |planet|
      enemy_ships = map.dangerous_enemy_ships(planet)
      next if enemy_ships.blank?

      defence_ships = map.can_defence_ships(planet)
      if defence_ships.present?
        defence_ships[0, enemy_ships.size].each_with_index do |ship, index|
          command_queue << ship.want_attack_enemy(map, enemy_ships[index])
        end
        next
      end
    end

    # For each idle ship we control
    me.idle_ships.each do |ship|

      unowned_planet = map.nearest_unowned_planet(ship)
      unfulled_planet = map.nearest_own_unfull_planet(ship)

      if unowned_planet && 
          ship.calculate_distance_between(unowned_planet) <= Game::Constants::MAX_ALLOW_WANT_DOCK_DISTANCE &&
          (
            unfulled_planet.nil? || 
            ship.calculate_distance_between(unowned_planet) < 
              ship.calculate_distance_between(unfulled_planet) * (3 + unowned_planet.spots_size)
          )
        command_queue << ship.want_dock_planet(map, unowned_planet)
        next
      end

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

  rescue Exception => e
    MyLog.info e.message
    e.backtrace.each{ |m| MyLog.info m }
  end
end
