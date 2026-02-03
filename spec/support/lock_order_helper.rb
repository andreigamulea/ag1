# frozen_string_literal: true

# spec/support/lock_order_helper.rb
#
# Helper pentru verificarea lock order in teste.
# Centralizează regex-urile pentru a le ajusta într-un singur loc.

module LockOrderHelper
  # Regex pentru ORDER BY id - strict: acceptă doar:
  # - id
  # - variants.id
  # - "variants"."id"
  ORDER_BY_ID = /
    order\s+by\s+
    (?:
      (?:["`]?\w+["`]?\.)?
      (?:["`]?variants["`]?\.)?
      ["`]?id["`]?
      |
      ["`]?id["`]?
    )
    (?=\s|$|,|\)|;)
  /imx

  # Regex pentru FOR UPDATE
  FOR_UPDATE = /for\s+update(?:\s+of\b[^;]*)?/im

  # Regex pentru schema queries (de exclus)
  SCHEMA_QUERY = /pg_|sqlite_master|information_schema/i

  # Regex pentru SELECT ... FROM table ... FOR UPDATE
  def select_for_update_regex(table)
    escaped = Regexp.escape(table)
    /
      SELECT.*FROM\s+
      (?:["`]?\w+["`]?\.)?
      ["`]?#{escaped}["`]?
      (?=\s|$|,|\)|;)
      .*FOR\s+UPDATE
    /imx
  end

  # Verifică că cel puțin un query are FOR UPDATE + ORDER BY id
  def expect_lock_order!(queries, label:)
    has_lock_with_order = queries.any? { |q|
      q =~ FOR_UPDATE && q =~ ORDER_BY_ID
    }

    expect(has_lock_with_order).to be(true),
      "Expected #{label} to have FOR UPDATE + ORDER BY id, got:\n#{queries.join("\n")}"
  end

  # Capturează queries pe un tabel specific cu FOR UPDATE
  def capture_lock_queries(table, into:)
    pattern = select_for_update_regex(table)
    ->(*, payload) {
      sql = payload[:sql].to_s
      return if sql.empty?
      return if sql =~ SCHEMA_QUERY
      into << sql if sql =~ pattern
    }
  end

  # Skip helper pentru adapteri care nu suportă FOR UPDATE (ex: SQLite)
  def skip_unless_supports_for_update!
    unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i
      skip "Adapter doesn't support SELECT FOR UPDATE"
    end
  end

  # Assert helper pentru READ COMMITTED isolation level
  def assert_read_committed!
    return unless ActiveRecord::Base.connection.adapter_name =~ /postgres/i

    iso = ActiveRecord::Base.connection.select_value("SHOW transaction_isolation")
    expect(iso).to match(/read committed/i),
      "Lock-order design assumes READ COMMITTED, got: #{iso}."
  end
end

RSpec.configure do |config|
  config.include LockOrderHelper
end
