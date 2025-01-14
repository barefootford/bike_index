class ParamsNormalizer
  def self.boolean(param = nil)
    return false if param.blank?
    ActiveRecord::Type::Boolean.new.cast(param.to_s.strip)
  end

  def self.present_or_false?(val)
    val.to_s.present?
  end
end
