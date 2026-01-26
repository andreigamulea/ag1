# Dezactivează autocomplete="off" pe hidden fields pentru a evita erori de validare HTML5
# Rails adaugă implicit acest atribut, dar HTML5 validator îl consideră invalid pe type="hidden"

Rails.application.config.action_view.automatically_disable_submit_tag = false

# Override pentru hidden_field_tag să nu includă autocomplete
module ActionView
  module Helpers
    module FormTagHelper
      alias_method :original_hidden_field_tag, :hidden_field_tag

      def hidden_field_tag(name, value = nil, options = {})
        options = options.stringify_keys
        options.delete("autocomplete")
        original_hidden_field_tag(name, value, options.symbolize_keys)
      end
    end
  end
end
