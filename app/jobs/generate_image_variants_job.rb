class GenerateImageVariantsJob < ApplicationJob
  queue_as :default

  def perform(attachment, resize_dimensions)
    return unless attachment && attachment.variable? && attachment.blob.present?

    # Procesare variantă
    attachment.variant(resize_to_limit: resize_dimensions).processed

    # Opțional: forțăm GC doar dacă este necesar
    GC.start(full_mark: true, immediate_sweep: true) if Rails.env.production?
  end
end