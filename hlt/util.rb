class Numeric
  def angle_rad_to_deg_clipped
    (self * 180.0 / Math::PI).round.modulo(360)
  end
end

class Object
  def blank?
    return true if nil?
    return empty? if respond_to? :empty?
    return self == '' if is_a? String
    false
  end

  def present?
    !blank?
  end
end
