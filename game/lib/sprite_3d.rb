class Array
  def z
    value(2)
  end

  def z=(value)
    self[2] = value
  end
end

class Sprite3D < Resources::Sprite
  attr_reader :z

  class << self
    def camera_distance
      @camera_distance ||= 500
    end
  end

  def z=(value)
    distance = Sprite3D.camera_distance - value
    @z_factor = distance / Sprite3D.camera_distance
    @z = value
  end

  def w
    @w * @z_factor
  end

  def h
    @h * @z_factor
  end
end
