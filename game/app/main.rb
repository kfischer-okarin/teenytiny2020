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

class World
  RADIUS = 320
  TURN_SPEED = 0.01
  WALK_SPEED = 0.02

  def initialize
    @particles = 200.times.map { random_particle }
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
    args.outputs.sprites << @sorted_particles
    args.outputs.sprites << @character
  end

  %i[turn_left turn_right forward back].each do |action|
    define_method action do
      quaternion = @quaternions[action]

      @particles.each do |particle|
        quaternion.apply_to(particle)
        @sorted_particles.fix_sort_order(particle)
      end
    end
  end

  private

  def random_particle
    polar = rand * Math::PI
    azimuth = rand * 2 * Math::PI

    Particle.at_polar_coordinates(RADIUS, polar, azimuth)
  end
end

class MainScene
  def initialize
    @world = World.new
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

def tick(args)
  args.state.scene ||= MainScene.new if args.tick_count.zero?

  args.state.scene.tick(args)
end
