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


class Array
  def min_distance(target=nil, &block)
    return first if length < 2

    _min = first
    0.upto(length - 2) do |index|
      current, _next = at(index), at(index + 1)
      res = block_given? ? yield(current, _next, target) : current.compare(_next, target)
      _min = res > 0 ? _next : current
    end
    _min
    # each { |entity| entity.with = target }

    # min(&block)
  end
end
