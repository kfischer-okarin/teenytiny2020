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

  def touched?
    @touched
  end

  def touch
    self.r, self.g, self.b = [255, 0, 0]
    @touched = true
  end

  def distance_from_center
    Math.sqrt(@x**2 + @y**2 + @z**2)
  end

  def square_distance_to(other)
    (@x - other.x)**2 + (@y - other.y)**2 + (@z - other.z)**2
  end

  def dot_product(other)
    x * other.x + y * other.y + z * other.z
  end

  def angle_distance_to(other_particle)
    length = other_length = World::RADIUS
    Math.acos(dot_product(other_particle) / (length * other_length))
  end

  def draw_override(ffi_draw)
    return if @z <= 0

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
    @segments = (-World::RADIUS..World::RADIUS).flat_map { |y|
      angle = Math.acos(y / World::RADIUS)
      x = Math.sin(angle) * World::RADIUS
      Segment.create_for(3, x, y)
    }
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
    def self.create_for(n, x, y)
      w = x * 2 / n
      n.times.map { |k|
        Segment.new(-x + k * w, y, w)
      }
    end

    def initialize(x, y, w)
      @y = y
      @x = x
      @w = w
      @h = 1
      @sphere_point_start = calc_sphere_point(@x, @y)
      @sphere_point_end = calc_sphere_point(@x + @w, @y)
      @uv_start = uv(@sphere_point_start)
      @uv_end = uv(@sphere_point_end)
      @source_x = 512 - (0.5 - @uv_start.x) * 512
      @source_y = 512 - (@uv_start.y - 0.5) * 512
      @source_w = calc_source_w
      @source_h = 1
      @path = 'planet'
    end

    def draw(ffi_draw)
      ffi_draw.draw_sprite_3 640 + @x, 360 + @y, @w.ceil, @h, @path,
                             # angle, alpha, red_saturation, green_saturation, blue_saturation
                             nil, nil, nil, nil, nil,
                             # tile_x, tile_y, tile_w, tile_h
                             nil, nil, nil, nil,
                             # flip_horizontally, flip_vertically,
                             nil, nil,
                             # angle_anchor_x, angle_anchor_y,
                             nil, nil,
                             # source_x, source_y, source_w, source_h
                             @source_x, @source_y, @source_w, @source_h
    end

    private

    # Calc ray sphere intersection
    # origin = [@x, @y, World::Radius]
    # direction = [0, 0, -1]
    # target = [origin.x, origin.y, origin.z - n]
    # origin.x ** 2 + origin.y ** 2 + (origin.z - n) ** 2 = World::RADIUS ** 2
    # n ** 2 - 2 * origin.z * n + (origin.x ** 2 + origin.y ** 2 + origin.z ** 2 - World::RADIUS ** 2)
    # n1 = origin.z + Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)
    # n2 = origin.z - Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)
    # target = [origin.x, origin.y, Math.sqrt(World::RADIUS ** 2 - origin.x ** 2 - origin.y ** 2)]
    def calc_sphere_point(x, y)
      radius = World::RADIUS
      [
        x / radius,
        y / radius,
        Math.sqrt([radius**2 - x**2 - y**2, 0].max) / radius
      ]
    end

    def uv(sphere_point)
      [
        0.5 + Math.atan2(sphere_point.x, sphere_point.z) / (2 * Math::PI),
        0.5 - Math.asin(sphere_point.y) / Math::PI
      ]
    end

    def calc_source_w
      right_x = @uv_end.x
      left_x = @uv_start.x
      right_x += 1 if right_x < left_x
      (right_x - left_x) * 512
    end
  end
end

class World
  RADIUS = 320
  TURN_SPEED = 0.03
  WALK_SPEED = 0.03

  def initialize(particles)
    @background = Background.new
    @particles = particles
    @sorted_particles = BubbleSortedList.new(@particles) { |particle| particle.z }

    @character = Particle.new(x: 0, y: 0, z: RADIUS, r: 0, g: 255, b: 0)

    @quaternions = {
      turn_left: DRT::Quaternion.from_angle_and_axis(-TURN_SPEED, 0, 0, 1),
      turn_right: DRT::Quaternion.from_angle_and_axis(TURN_SPEED, 0, 0, 1),
      forward: DRT::Quaternion.from_angle_and_axis(-WALK_SPEED, -1, 0, 0),
      back: DRT::Quaternion.from_angle_and_axis(WALK_SPEED, -1, 0, 0)
    }
  end

  def finished?
    @particles.all?(&:touched?)
  end


  def render(args)
    args.outputs.sprites << @background
    args.outputs.sprites << @sorted_particles
    args.outputs.sprites << @character
  end

  def tick(args)
    most_front_particle = @sorted_particles.value(-1)
    if most_front_particle.square_distance_to(@character) < 1000
      most_front_particle.touch
    end
  end

  %i[turn_left turn_right forward back].each do |action|
    define_method action do
      apply_quaternion @quaternions[action]
    end
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

  def initialize(planet_texture)
    @planet_texture = planet_texture
    @world = World.new(ParticleFactory.random_spaced(15, Math::PI / 9))
    @remaining_time = 20.0
    @state = :game
  end

  def tick(args)
    case @state
    when :game
      @remaining_time = [@remaining_time - 0.016, 0].max
      process_input(args)

      @inputs.each do |input|
        @world.send(input)
        @planet_texture.send(input)
      end
      @world.tick(args)
      @planet_texture.tick(args)

      @state = :win if @world.finished?
      @state = :game_over if @remaining_time.zero?

    when :win, :game_over
      if args.inputs.keyboard.key_down.space
        @next_scene = MainScene.new(@planet_texture)
      end
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
    args.outputs.labels << { x: 150, y: 330, text: format("%.2f", @remaining_time), size_enum: 8, r: 255, g: 255, b: 255 }

    case @state
    when :win
      args.outputs.labels << { x: 120, y: 700, text: "You win.", size_enum: 8, r: 255, g: 255, b: 255 }
      args.outputs.labels << { x: 10, y: 650, text: "Press Space to restart", size_enum: 8, r: 255, g: 255, b: 255 }
    when :game_over
      args.outputs.labels << { x: 120, y: 700, text: "You lose.", size_enum: 8, r: 255, g: 255, b: 255 }
      args.outputs.labels << { x: 10, y: 650, text: "Press Space to restart", size_enum: 8, r: 255, g: 255, b: 255 }
    end

    render_texture(args) if args.debug.active?
  end

  private

  def render_texture(args)
    args.outputs.primitives << [0, 0, 128, 128, 255, 255, 255].solid
    args.outputs.primitives << [0, 0, 128, 128, 'planet'].sprite
  end
end

class LoopingTexture
  attr_reader :offset_x, :offset_y, :angle

  def initialize(args)
    @path = Resources.sprites.mars.path
    @size = 512
    @offset_x = 0
    @offset_y = 0
    self.angle = 0
    redraw(args)
  end

  def forward
    self.offset_x -= @direction.x * 2
    self.offset_y -= @direction.y * 2
  end

  def back
    self.offset_x += @direction.x * 2
    self.offset_y += @direction.y * 2
  end

  def offset_x=(value)
    @offset_x = value
    @offset_x += @size while @offset_x <= -@size / 2
    @offset_x -= @size while @offset_x >= @size / 2
    @dirty = true
    @offset_x
  end

  def offset_y=(value)
    @offset_y = value
    @offset_y += @size while @offset_y <= -@size / 2
    @offset_y -= @size while @offset_y >= @size / 2
    @dirty = true
    @offset_y
  end

  def angle=(value)
    @angle = value % 360
    radians = @angle.to_radians
    @direction = [Math.sin(radians), Math.cos(radians)]
    @dirty = true
    @angle
  end

  def turn_left
    self.angle -= 1
  end

  def turn_right
    self.angle += 1
  end

  def tick(args)
    redraw(args) if @dirty
  end

  private

  def redraw(args)
    target = args.outputs[:planet_first_pass]
    target.width = @size * 2
    target.height = @size * 2
    2.times do |x|
      2.times do |y|
        target.primitives << {
          x: @size * x + @offset_x,
          y: @size * y + @offset_y,
          w: @size,
          h: @size,
          path: @path,
        }.sprite
      end
    end
    target.primitives << [@size - 50 + @offset_x, @size - 50 + @offset_y, 100, 100, 255, 0, 0].solid if args.debug.active?

    target = args.outputs[:planet]
    target.width = @size * 2
    target.height = @size * 2
    target.primitives << [0, 0, @size * 2, @size * 2, :planet_first_pass, @angle].sprite
    @dirty = false
  end
end

class PrepareRenderTargets
  def tick(args)
    texture = LoopingTexture.new(args)
    @next_scene = MainScene.new(texture)
  end

  def next_scene
    @next_scene
  end
end

def tick(args)
  args.state.scene ||= PrepareRenderTargets.new if args.tick_count.zero?

  scene = args.state.scene
  scene.tick(args)
  args.state.scene = scene.next_scene if scene.next_scene
end
