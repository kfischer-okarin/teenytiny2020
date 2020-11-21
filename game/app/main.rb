require 'lib/bubble_sorted_list.rb'
require 'lib/debug_mode.rb'
require 'lib/extra_keys.rb'
require 'lib/quaternion.rb'
require 'lib/resources.rb'
require 'lib/sprite_resources.rb'
require 'lib/sprite_3d.rb'

require 'app/resources.rb'

class MainScene
  def initialize
    @particles = 200.times.map { random_particle }
    @sorted_particles = BubbleSortedList.new(@particles) { |particle| -particle.z }
  end

  def tick(args)
    render(args)
  end

  private

  def render(args)
    args.outputs.background_color = [0, 0, 0]
    args.outputs.sprites << @sorted_particles
  end

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
      return if @z_factor < 1

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

  def random_particle
    radius = 300
    polar = rand * Math::PI
    azimuth = rand * 2 * Math::PI

    Particle.at_polar_coordinates(radius, polar, azimuth)
  end
end

def tick(args)
  args.state.scene ||= MainScene.new if args.tick_count.zero?

  args.state.scene.tick(args)
end
