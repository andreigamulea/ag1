# app/jobs/generate_image_variants_job.rb
class GenerateImageVariantsJob < ApplicationJob
  queue_as :default
  def perform(blob_id, resize_dimensions)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob && blob.variable?
    Rails.logger.debug "Processing variant for blob #{blob.key} with dimensions: #{resize_dimensions}"
    blob.variant(resize_to_limit: resize_dimensions).processed
    blob = nil # Eliberează referința
    GC.start # Forțează garbage collection
  rescue StandardError => e
    Rails.logger.error "Error processing variant for blob #{blob&.key}: #{e.message}"
  ensure
    GC.start # Forțează garbage collection la final
  end
end