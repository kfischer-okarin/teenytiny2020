require 'lib/bubble_sorted_list.rb'
require 'lib/debug_mode.rb'
require 'lib/extra_keys.rb'
require 'lib/quaternion.rb'
require 'lib/resources.rb'
require 'lib/sprite_resources.rb'
require 'lib/sprite_3d.rb'

require 'app/resources.rb'

class Particle < Sprite3D
  def self.at_polar_coordinates(radius, polar, azimuth)
    sin_polar = Math.sin(polar)

    new(
      x: radius * sin_polar * Math.cos(azimuth),
      y: radius * sin_polar * Math.sin(azimuth),
      z: radius * Math.cos(polar)
    )
  end

  def initialize(values)
    attributes = { w: 64, h: 64 }
    attributes.update(values) if values

    super(Resources.sprites.particle, attributes)
  end

  def distance_from_center
    Math.sqrt(@x**2 + @y**2 + @z**2)
  end

  def dot_product(other)
    x * other.x + y * other.y + z * other.z
  end

  def angle_distance_to(other_particle)
    length = other_length = World::RADIUS
    Math.acos(dot_product(other_particle) / (length * other_length))
  end

  def draw_override(ffi_draw)
    return if @z >= 0

    actual_w = w
    actual_h = h
    # x, y, w, h, path
    ffi_draw.draw_sprite_3 @x + 640 - actual_w.half, @y + 360 - actual_h.half, actual_w, actual_h, path,
                           # angle, alpha, red_saturation, green_saturation, blue_saturation
                           nil, nil, r, g, b,
                           # tile_x, tile_y, tile_w, tile_h
                           nil, nil, nil, nil,
                           # flip_horizontally, flip_vertically,
                           nil, nil,
                           # angle_anchor_x, angle_anchor_y,
                           nil, nil,
                           # source_x, source_y, source_w, source_h
                           nil, nil, nil, nil
  end
end

class Background
  def initialize
    @path = 'planet'
    @segments = (-World::RADIUS..World::RADIUS).flat_map { |y|
      angle = Math.acos(y / World::RADIUS)
      x = Math.sin(angle) * World::RADIUS
      Segment.create_for(self, 3, x, y)
    }
  end

  def forward
    @center_y += 2
    @center_y -= 1024 if @center_y >= 1024 + 512
  end

  def back
    @center_y -= 2
    @center_y += 1024 if @center_y <= 1024 - 512
  end

  def center_x
    @center_x ||= 1024
  end

  def center_y
    @center_y ||= 1024
  end

  def primitive_marker
    :sprite
  end

  def draw_override(ffi_draw)
    @segments.each do |segment|
      segment.draw(ffi_draw)
    end
  end

  private

  class Segment
    def self.create_for(background, n, x, y)
      w = x * 2 / n
      n.times.map { |k|
        Segment.new(background, -x + k * w, y, w)
      }
    end

    def initialize(background, x, y, w)
      @background = background
      @y = y
      @x = x
      @w = w
      @h = 1
      @sphere_point_start = calc_sphere_point(@x, @y)
      @sphere_point_end = calc_sphere_point(@x + @w, @y)
      @uv_start = uv(@sphere_point_start)
      @uv_end = uv(@sphere_point_end)
      @source_w = calc_source_w
      @source_h = 1
      @path = 'planet'
    end

    def source_x
      @background.center_x - (0.5 - @uv_end.x) * 512
    end

    def source_y
      @background.center_y - (@uv_end.y - 0.5) * 512
    end

    def draw(ffi_draw)
      ffi_draw.draw_sprite_3 640 + @x, 360 + @y, @w.ceil, @h, @path,
                             # angle, alpha, red_saturation, green_saturation, blue_saturation
                             nil, nil, nil, nil, nil,
                             # tile_x, tile_y, tile_w, tile_h
                             nil, nil, nil, nil,
                             # flip_horizontally, flip_vertically,
                             true, nil,
                             # angle_anchor_x, angle_anchor_y,
                             nil, nil,
                             # source_x, source_y, source_w, source_h
                             source_x, source_y, @source_w, @source_h
    end

    private

    # Calc ray sphere intersection
    # origin = [@x, @y, -World::Radius]
    # direction = [0, 0, 1]
    # target = [origin.x, origin.y, origin.z + n]
    # origin.x ** 2 + origin.y ** 2 + (origin.z + n) ** 2 = World::RADIUS ** 2
    # n ** 2 + 2 * origin.z * n + (origin.x ** 2 + origin.y ** 2 + origin.z ** 2 - World::RADIUS ** 2)
    # n1 = - origin.z + Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)
    # n2 = - origin.z - Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)
    # target = [origin.x, origin.y, -Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)]
    def calc_sphere_point(x, y)
      radius = World::RADIUS
      [
        x / radius,
        y / radius,
        -Math.sqrt([radius**2 - x**2 - y**2, 0].max) / radius
      ]
    end

    def uv(sphere_point)
      [
        0.5 + Math.atan2(sphere_point.x, sphere_point.z) / (2 * Math::PI),
        0.5 - Math.asin(sphere_point.y) / Math::PI
      ]
    end

    def calc_source_w
      right_x = @uv_start.x
      left_x = @uv_end.x
      right_x += 1 if right_x < left_x
      (right_x - left_x) * 512
    end
  end
end

class World
  RADIUS = 320
  TURN_SPEED = 0.01
  WALK_SPEED = 0.02

  def initialize(particles)
    @background = Background.new
    @particles = particles
    @sorted_particles = BubbleSortedList.new(@particles) { |particle| -particle.z }

    @character = Particle.new(x: 0, y: 0, z: -RADIUS, r: 0, g: 255, b: 0)

    @quaternions = {
      turn_left: DRT::Quaternion.from_angle_and_axis(-TURN_SPEED, 0, 0, 1),
      turn_right: DRT::Quaternion.from_angle_and_axis(TURN_SPEED, 0, 0, 1),
      forward: DRT::Quaternion.from_angle_and_axis(WALK_SPEED, -1, 0, 0),
      back: DRT::Quaternion.from_angle_and_axis(-WALK_SPEED, -1, 0, 0)
    }
  end

  def render(args)
    args.outputs.sprites << @background
    args.outputs.sprites << @sorted_particles
    args.outputs.sprites << @character
  end

  %i[turn_left turn_right].each do |action|
    define_method action do
      apply_quaternion @quaternions[action]
    end
  end

  def forward
    apply_quaternion @quaternions[:forward]
    @background.forward
  end

  def back
    apply_quaternion @quaternions[:back]
    @background.back
  end

  private

  def apply_quaternion(quaternion)
    @particles.each do |particle|
      quaternion.apply_to(particle)
      @sorted_particles.fix_sort_order(particle)
    end
  end
end

class ParticleFactory
  class << self
    def random
      polar = rand * Math::PI
      azimuth = rand * 2 * Math::PI

      Particle.at_polar_coordinates(World::RADIUS, polar, azimuth)
    end

    def random_spaced(n, minimum_angle)
      [].tap { |result|
        n.times do
          new_particle = nil
          loop do
            new_particle = random
            break if result.all? { |particle| particle.angle_distance_to(new_particle) >= minimum_angle }
          end
          result << new_particle
        end
      }
    end
  end
end

class MainScene
  attr_reader :next_scene

  def initialize
    @world = World.new(ParticleFactory.random_spaced(20, Math::PI / 9))
  end

  def tick(args)
    process_input(args)

    @inputs.each do |input|
      @world.send(input)
    end

    render(args)
  end

  private

  def process_input(args)
    @inputs = []
    if args.inputs.keyboard.key_held.left
      @inputs << :turn_left
    elsif args.inputs.keyboard.key_held.right
      @inputs << :turn_right
    end
    if args.inputs.keyboard.key_held.up
      @inputs << :forward
    elsif args.inputs.keyboard.key_held.down
      @inputs << :back
    end
  end

  def render(args)
    args.outputs.background_color = [0, 0, 0]
    @world.render(args)
  end
end

class PrepareRenderTargets
  def tick(args)
    planet = args.outputs[:planet]
    planet.width = 2048
    planet.height = 2048
    4.times do |x|
      4.times do |y|
        planet.sprites << [512 * x, 512 * y, 512, 512, Resources.sprites.mars.path]
      end
    end
  end

  def next_scene
    MainScene.new
  end
end
def tick(args)
  args.state.scene ||= PrepareRenderTargets.new if args.tick_count.zero?

  scene = args.state.scene
  scene.tick(args)
  args.state.scene = scene.next_scene if scene.next_scene
end
