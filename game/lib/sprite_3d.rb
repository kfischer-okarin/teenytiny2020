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
      1000
    end
  end

  def z=(value)
    distance_from_camera = Sprite3D.camera_distance - value
    @z_factor = Sprite3D.camera_distance / distance_from_camera
    @z = value
  end

  def w
    @w * @z_factor
  end

  def h
    @h * @z_factor
  end
end
