class BikeV2ShowSerializer < BikeV2Serializer
  attributes :registration_created_at,
    :registration_updated_at,
    :url,
    :api_url,
    :manufacturer_id,
    :paint_description,
    :name,
    :frame_size,
    :description,
    :rear_tire_narrow,
    :front_tire_narrow,
    :type_of_cycle,
    :test_bike,
    :rear_wheel_size_iso_bsd,
    :front_wheel_size_iso_bsd,
    :handlebar_type_slug,
    :frame_material_slug,
    :front_gear_type_slug,
    :rear_gear_type_slug,
    :additional_registration

  has_one :stolen_record

  has_many :public_images
  has_many :components

  def type_of_cycle
    object.cycle_type_name
  end

  def api_url
    "#{ENV["BASE_URL"]}/api/v1/bikes/#{object.id}"
  end

  def test_bike
    object.example
  end

  def registration_created_at
    object.created_at.to_i
  end

  def registration_updated_at
    object.updated_at.to_i
  end

  def stolen_record
    return nil unless current_stolen_record.present?
    StolenRecordV2Serializer.new(current_stolen_record, scope: scope, root: false, event: object)
  end

  def rear_wheel_size_iso_bsd
    object.rear_wheel_size&.iso_bsd
  end

  def front_wheel_size_iso_bsd
    object.front_wheel_size&.iso_bsd
  end

  def handlebar_type_slug
    object.handlebar_type
  end

  def front_gear_type_slug
    object.front_gear_type&.slug
  end

  def rear_gear_type_slug
    object.rear_gear_type&.slug
  end

  def frame_material_slug
    return nil unless object.frame_material.present?
    FrameMaterial.new(object.frame_material).slug
  end

  # Legacy name for the extra_registration_number column
  def additional_registration
    object.extra_registration_number
  end
end
