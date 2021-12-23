class MigrateOwnershipWorker < ApplicationWorker
  sidekiq_options queue: "low_priority", retry: false
  # This timestamp is when the migration started - so any ownership created *after* this timestamp
  # is assumed to be correct
  END_TIMESTAMP = 1640284743
  TO_ENQUEUE = (ENV["MIGRATE_OWNERSHIP_QUEUE"] || 2500).to_i

  def self.bikes
    Bike.unscoped.where("updated_at < ?", Time.at(END_TIMESTAMP)).order(updated_at: :desc)
  end

  def self.enqueue
    # Skip if the queue is backing up
    return if ScheduledWorker.enqueued?
    bikes.limit(TO_ENQUEUE)
      .pluck(:id).each { |id| MigrateCreationStateToOwnershipWorker.perform_async(id) }
  end

  def perform(bike_id)
    bike = Bike.unscoped.find_by_id(bike_id)
    return if bike.blank?
    bike.save
    new_info = (bike.current_ownership&.registration_info || {}).merge(bike.conditional_information)
    bike.current_ownership&.update(registration_info: new_info)
  end
end
