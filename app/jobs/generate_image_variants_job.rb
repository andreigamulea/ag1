class GenerateImageVariantsJob < ApplicationJob
  queue_as :default

  def perform(attachment, resize_dimensions)
    return unless attachment.variable?

    # Procesare variantă
    attachment.variant(resize_to_limit: resize_dimensions).processed

    # Opțional, forțăm curățarea memoriei
    GC.start(full_mark: true, immediate_sweep: true)
  end
end
