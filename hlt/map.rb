require 'player'
require 'planet'
require 'ship'
require 'position'

# Map which houses the current game information/metadata.

# my_id: Current player id associated with the map
# width: Map width
# height: Map height
class Map
  attr_reader :my_id, :width, :height

  def initialize(player_id, width, height)
    @my_id = player_id
    @width = width
    @height = height
    @players = {}
    @planets = {}
  end

  # return: Array of all players
  def players
    @players.values
  end

  # Fetch player by id
  # id: the id (integer) of the desired player
  # return: The player associated with id
  def player(id)
    @players[id]
  end

  # return: The bot's Player object
  def me
    player(my_id)
  end

  # return: Array of all Planets
  def planets
    @planets.values
  end

  def can_dock_planets
    @planets.values.select { |planet| planet.unowned? || (planet.owner_is(me) && planet.unfull?) }
  end

  def unowned_planets
    @planets.values.select(&:unowned?)
  end

  def own_planets
    @planets.values.select { |planet| planet.owner && planet.owner.id == me.id }
  end

  def enemy_planets
    @planets.values.select { |planet| planet.owner.nil? || planet.owner.id != me.id }
  end

  def enemy_ships
    (players - [me]).map(&:ships).flatten
  end

  def dangerous_enemy_ships(planet, distance=Game::Constants::CORDON_DISTANCE)
    enemy_ships.select { |ship| ship.undocked? && planet.calculate_distance_between(ship) <= distance }
      .sort! { |ship| planet.calculate_distance_between(ship) }
  end

  def can_defence_ships(planet, distance=Game::Constants::DEFENCE_DISTANCE)
    me.idle_ships.select { |ship| planet.calculate_distance_between(ship) <= distance }
      .sort! { |ship| planet.calculate_distance_between(ship) }
  end

  # Fetch a planet by ID
  # id: the ID of the desired planet
  # return: a Planet
  def planet(id)
    @planets[id]
  end

  def ships
    players.map(&:ships).flatten
  end

  def update(input)
    tokens = input.split
    @players, tokens = Player::parse(tokens)
    @planets, tokens = Planet::parse(tokens)

    raise if tokens.length != 0
    link
  end

  # Fetch all entities in relationship to the entered entity keyed by distance
  # entity: the source entity to find distances from
  # return: Hash containing all entities with their designated distances
  def nearby_entities_by_distance(entity, include_planet: true, include_ship: true, include_players: nil, need_idle: true)
    include_players ||= players

    entitys = []
    if include_planet
      include_player_ids = include_players.map(&:id)
      entitys += planets.values.select { |plant| plant.unowned? || include_player_ids.include?(planet.owner.id) }
    end

    if include_ship
      entitys += include_players.map(&(need_idle ? :idle_ships : :ships)).flatten
    end

    # any new key is initialized with an empty array
    result = Hash.new { |h, k| h[k] = [] }

    entitys.each do |foreign_entity|
      next if entity == foreign_entity
      result[entity.calculate_distance_between(foreign_entity)] << foreign_entity
    end
    result
  end

  # Check whether there is a straight-line path to the given point, without
  # obstacles in between.
  # ship: Source entity
  # target: target entity
  # ignore: Array of entity types to ignore
  # return: array of obstacles between the ship and target
  def obstacles_between(ship, target, ignore=[])
    obstacles = []
    entities = []
    entities.concat(planets) unless ignore.include?(:planets)
    entities.concat(ships) unless ignore.include?(:ships)

    entities.each do |foreign_entity|
      next if foreign_entity == ship || foreign_entity == target
      if intersect_segment_circle(ship, target, foreign_entity, fudge=ship.radius + 0.1)
        obstacles << foreign_entity
      end
    end
    obstacles
  end

  def nearest_unowned_planet(entity)
    unowned_planets.select(&:unwill_full?).min do |one, other|
      entity.calculate_distance_between(one) * 5 / one.docking_spots <=> entity.calculate_distance_between(other) * 5 / one.docking_spots
    end
  end

  def nearest_enemy_planet(entity)
    enemy_planets.min_distance(entity)# { |one, other| entity.calculate_distance_between(one) <=> entity.calculate_distance_between(other) }
  end

  def nearest_enemy_ship(entity)
    enemy_ships.select(&:unattacked?)
      .min_distance(entity)#{ |one, other| entity.calculate_distance_between(one) <=> entity.calculate_distance_between(other) }
  end

  def nearest_enemy_docked_ship(entity)
    enemy_ships.select(&:dock_status?)
      .min_distance(entity)#{ |one, other| entity.calculate_distance_between(one) <=> entity.calculate_distance_between(other) }
  end

  def nearest_own_unfull_planet(entity)
    own_planets.select(&:unwill_full?)
      .min_distance(entity)#{ |one, other| entity.calculate_distance_between(one) <=> entity.calculate_distance_between(other) }
  end

  def enemy_haste?(distance=Game::Constants::HASTE_DISTANCE)
    enemy_ships.size == 3 &&
      enemy_ships.all? { |enemy_ship| me.ships.all? { |ship| ship.calculate_distance_between(enemy_ship) <= distance } }
  end

  # A strategy for defence enemy haste strategy
  def defence_haste_strategy
    command_queue = []
    ships = me.ships
    enemies = enemy_ships

    if ships.all?(&:undocked?)
      command_queue <<  if ships_assembled?(ships)
                          ships.map{ |ship| ship.want_attack_enemy(self, enemies.first, Game::Constants::MAX_SPEED * 0.9) }
                        else
                          position = assemble_point(ships)
                          ships.map{ |ship| ship.aggregate(self, position) }
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
        command_queue << ship.aggregate(self, position)
      end
    end

    command_queue
  end

  def ships_assembled?(ships)
    sample_ship = ships.sample
    ships.all? do |ship|
      ship.calculate_distance_between(sample_ship) <= Game::Constants::MAX_FRIEND_DISTANCE + 3
    end
  end

  def assemble_point(ships)
    x = ships.map(&:x).reduce(:+) / ships.size
    y = ships.map(&:y).reduce(:+) / ships.size
    Position.new x, y
  end

  def select_point(entity, enemy)
    x = entity.x > enemy.x ? 7 : -7
    y = entity.y > enemy.y ? 7 : -7
    Position.new entity.x + x, entity.y + y
  end

  private

  # Update each ship + planet with the completed player and planet objects
  def link
    (planets + ships).each do |entity|
      entity.link(@players, @planets)
    end
  end

  # Test whether a line segment and circle intersect.
  # alpha: The start of the line segment. (Needs x, y attributes)
  # omega: The end of the line segment. (Needs x, y attributes)
  # circle: The circle to test against. (Needs x, y, r attributes)
  # fudge: A fudge factor; additional distance to leave between the segment and circle.
  #        (Probably set this to the ship radius, 0.5.)
  # return: True if intersects, False otherwise
  def intersect_segment_circle(alpha, omega, circle, fudge=0.5)
    dx = omega.x - alpha.x
    dy = omega.y - alpha.y

    a = dx**2 + dy**2
    b = -2 * (alpha.x**2 - alpha.x*omega.x - alpha.x*circle.x + omega.x*circle.x +
              alpha.y**2 - alpha.y*omega.y - alpha.y*circle.y + omega.y*circle.y)
    c = (alpha.x - circle.x)**2 + (alpha.y - circle.y)**2

    if a == 0.0
      # Start and end are the same point
      return alpha.calculate_distance_between(circle) <= circle.radius + fudge
    end

    # Time along segment when closest to the circle (vertex of the quadratic)
    t = [-b / (2 * a), 1.0].min
    if t < 0
      return false
    end

    closest_x = alpha.x + dx * t
    closest_y = alpha.y + dy * t
    closest_distance = Position.new(closest_x, closest_y).calculate_distance_between(circle)

    return closest_distance <= circle.radius + fudge
  end
end
