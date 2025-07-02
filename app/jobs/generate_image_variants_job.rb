# app/jobs/generate_image_variants_job.rb
class GenerateImageVariantsJob < ApplicationJob
  queue_as :default

  def perform(attachment)
    return unless attachment.variable?

    # Creează varianta și o procesează acum
    attachment.variant(resize_to_limit: [300, 300]).processed
  end
end
