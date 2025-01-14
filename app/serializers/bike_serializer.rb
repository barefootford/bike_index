class BikeSerializer < ApplicationSerializer
  attributes :id,
    :serial,
    :registration_created_at,
    :registration_updated_at,
    :url,
    :api_url,
    :manufacturer_name,
    :manufacturer_id,
    :frame_colors,
    :paint_description,
    :stolen,
    :name,
    :year,
    :frame_model,
    :frame_size,
    :description,
    :rear_tire_narrow,
    :front_tire_narrow,
    :photo,
    :thumb,
    :title,
    :type_of_cycle,
    :frame_material,
    :handlebar_type

  has_one :rear_wheel_size,
    :front_wheel_size,
    :front_gear_type,
    :rear_gear_type,
    :stolen_record

  def serial
    object.serial_display
  end

  def type_of_cycle
    object.cycle_type_name
  end

  def manufacturer_name
    object.mnfg_name
  end

  def url
    object.html_url
  end

  def api_url
    "#{ENV["BASE_URL"]}/api/v1/bikes/#{object.id}"
  end

  def title
    object.title_string + "(#{object.frame_colors.to_sentence.downcase})"
  end

  def registration_created_at
    object.created_at
  end

  def registration_updated_at
    object.updated_at
  end

  def stolen
    object.status_stolen?
  end

  def stolen_record
    object.current_stolen_record if object.current_stolen_record.present?
  end

  def photo
    if object.public_images.present?
      object.public_images.first.image_url(:large)
    elsif object.stock_photo_url.present?
      object.stock_photo_url
    end
  end

  def thumb
    if object.public_images.present?
      object.public_images.first.image_url(:small)
    elsif object.stock_photo_url.present?
      small = object.stock_photo_url.split("/")
      ext = "/small_" + small.pop
      small.join("/") + ext
    end
  end

  def frame_material
    object.frame_material_name
  end

  def handlebar_type
    object.handlebar_type_name
  end
end
