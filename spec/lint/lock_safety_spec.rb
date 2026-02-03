# frozen_string_literal: true

require 'rails_helper'

# spec/lint/lock_safety_spec.rb
#
# Scanează codebase-ul pentru pattern-uri periculoase de locking.
# IMPORTANT: Scanăm PER FIȘIER pentru a evita false positives din concatenare.

RSpec.describe "Lock safety patterns" do
  def scan_app_files(pattern, context_chars: 120)
    matches = []

    Dir["app/**/*.rb"].each do |file_path|
      content = File.read(file_path)
      content.scan(pattern) do
        m = Regexp.last_match
        from = [m.begin(0) - context_chars, 0].max
        to   = [m.end(0) + context_chars, content.length].min
        matches << {
          file: file_path,
          match: m[0],
          context: content[from...to]
        }
      end
    end

    matches
  end

  def format_matches(matches)
    matches.map { |m| "#{m[:file]}:\n#{m[:context]}" }.join("\n\n---\n\n")
  end

  it "does not use product.variants.lock without order(:id)" do
    # Pattern periculos: .variants.lock sau .variants.lock! fără .order(:id)
    dangerous_pattern = /\.variants\b(?:(?!\.order\(:id\)).)*?\.lock\b/m

    matches = scan_app_files(dangerous_pattern)

    expect(matches).to be_empty,
      "Found unsafe locking pattern (variants.lock without order(:id)):\n\n#{format_matches(matches)}"
  end

  it "does not use Variant.where(...).update_all without prior lock" do
    # Pattern periculos: update_all pe multiple variante fără SELECT FOR UPDATE
    dangerous_pattern = /Variant\.where\(.*\)\.update_all/

    matches = scan_app_files(dangerous_pattern)

    # Warning, nu failure (heuristic - trebuie verificat manual)
    if matches.any?
      warn "Found Variant.where().update_all patterns - verify each has prior locking:\n\n#{format_matches(matches)}"
    end
  end

  it "does not lock variant before product (V->P ordering)" do
    # Pattern periculos: variant.lock! urmat de variant.product.lock!
    # Asta creează ordonare V→P care face deadlock cu P→V flows
    dangerous_pattern = /variant\.lock!.*variant\.product\.lock!/m

    matches = scan_app_files(dangerous_pattern)

    expect(matches).to be_empty,
      "Found V->P lock ordering (variant.lock! before product.lock!) - this causes deadlock:\n\n#{format_matches(matches)}"
  end
end
