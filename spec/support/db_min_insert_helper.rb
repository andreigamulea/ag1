# frozen_string_literal: true

require 'securerandom'

module DbMinInsertHelper
  def postgres?
    ActiveRecord::Base.connection.adapter_name =~ /postgres/i
  end

  # Inserează un rând cu valori "safe" pentru toate coloanele NOT NULL fără default.
  # overrides: valori impuse (ex: status: 'pending', order_id: 1)
  def insert_min_row!(table, overrides: {})
    conn = ActiveRecord::Base.connection
    pk   = conn.primary_key(table)

    cols = conn.columns(table)
    needed = cols.select do |c|
      c.name != pk && !c.null && c.default.nil? && !overrides.key?(c.name.to_sym)
    end

    attrs = {}
    needed.each { |c| attrs[c.name.to_sym] = sample_value_for(c) }
    attrs.merge!(overrides)

    names  = attrs.keys.map(&:to_s)
    values = attrs.values.map { |v| conn.quote(v) }

    sql = +"INSERT INTO #{table} (#{names.join(',')}) VALUES (#{values.join(',')})"
    if postgres?
      sql << " RETURNING #{pk}"
      conn.select_value(sql).to_i
    else
      conn.insert(sql)
      conn.select_value("SELECT #{pk} FROM #{table} ORDER BY #{pk} DESC LIMIT 1").to_i
    end
  end

  def sample_value_for(column)
    # valori deterministe & compatibile cu majoritatea schemelor
    case column.type
    when :string, :text
      if column.name == 'status'
        'pending' # important: status enum cu stringuri
      else
        "rspec_#{SecureRandom.hex(6)}"
      end
    when :integer, :bigint
      1
    when :decimal, :float
      0
    when :boolean
      false
    when :datetime, :timestamp
      Time.current
    when :date
      Date.current
    else
      # fallback: string
      "rspec_#{SecureRandom.hex(6)}"
    end
  end
end

RSpec.configure do |config|
  config.include DbMinInsertHelper
end
