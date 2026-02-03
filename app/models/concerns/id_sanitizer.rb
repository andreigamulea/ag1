# frozen_string_literal: true

# app/models/concerns/id_sanitizer.rb
#
# Shared helper pentru sanitizarea ID-urilor.
# Centralizat aici pentru a evita drift între servicii.
# FAIL-FAST: Input invalid ridică ArgumentError, nu "silent drop".
#
# SINGLE-SOURCE: Logica e definită O SINGURĂ DATĂ în ClassMethods.
# Instance method-ul delegă la class method pentru zero drift.
#
# CONTRACT EXPLICIT:
# - nil / "" / "  " (whitespace-only) → DROP (skip, nu ArgumentError)
# - "abc" / "1.5" / "0x10" → ArgumentError (invalid format)
# - "123" / 123 (Integer) → accept (conversie la Integer)
# - Mixed array ["1", 2, nil, "  "] → [1, 2] (drop nil/whitespace, conversie restul)

module IdSanitizer
  extend ActiveSupport::Concern

  # Instance method delegă la class method (SINGLE-SOURCE pattern)
  def sanitize_ids(input)
    self.class.sanitize_ids(input)
  end
  private :sanitize_ids

  module ClassMethods
    # Sanitizează un array de IDs pentru operații pe variante/opțiuni.
    # FAIL-FAST semantics:
    # - nil / "" / " " → ignorate (drop)
    # - "abc" / "1.5"  → ArgumentError (Integer parse fail)
    # - "0x10" / "1_000" → ArgumentError (H1: doar decimal strict)
    # - 0 / -1         → ArgumentError explicit
    # - "123" / 123    → OK
    #
    # H1 HARDENING: Integer() în Ruby acceptă forme "surpriză":
    # - Integer("0x10") → 16 (hex)
    # - Integer("0b101") → 5 (binary)
    # - Integer("0o17") → 15 (octal)
    # - Integer("1_000") → 1000 (underscore separator)
    # Dacă ID-urile vin din feed-uri externe, acestea pot fi foot-guns.
    # Validăm strict: doar cifre decimale (opțional cu leading/trailing whitespace).
    #
    # @param input [Array, nil] Array de ID-uri (poate fi nil)
    # @return [Array<Integer>] Array sortat de ID-uri pozitive unice
    # @raise [ArgumentError] dacă un ID nu e valid
    STRICT_DECIMAL_REGEX = /\A-?\d+\z/.freeze  # Permite: "0", "123", "-1", dar NU "0x10", "1_000", "1.5"

    def sanitize_ids(input)
      Array(input).map { |x|
        s = x.to_s.strip
        next nil if s.empty?  # ← DROP explicit (nu error) pentru nil/""/whitespace

        # H1: Validare strictă - doar cifre decimale (cu opțional minus), fără hex/octal/binary/underscore
        # Permite: "0", "1", "123", "-1" (dar minus/zero vor fi respinse mai jos)
        # Respinge: "0x10", "0b101", "0o17", "1_000", "1.5", "abc"
        unless s.match?(STRICT_DECIMAL_REGEX)
          raise ArgumentError, "ID must be decimal digits only (no hex/octal/underscore), got: #{s.inspect}"
        end

        # Respinge leading zero (ex: "01", "007") - EXCEPT pentru "0" singur sau "-0"
        if s.match?(/\A-?0\d+\z/)
          raise ArgumentError, "ID must be decimal digits only (no hex/octal/underscore), got: #{s.inspect}"
        end

        id = Integer(s)  # Acum e safe - am validat formatul
        raise ArgumentError, "ID must be positive integer, got: #{id}" unless id > 0
        id
      }.compact.uniq.sort
    end
  end
end
