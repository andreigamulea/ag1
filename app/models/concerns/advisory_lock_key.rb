# frozen_string_literal: true

# app/models/concerns/advisory_lock_key.rb
#
# Shared helper pentru advisory lock key generation.
# Centralizat aici pentru a evita drift între servicii.
# NOTA: Acest modul nu folosește Zlib direct, deci nu are nevoie de `require 'zlib'`.
# REGULA: Orice fișier care apelează Zlib.crc32() trebuie să aibă `require 'zlib'` local.

module AdvisoryLockKey
  extend ActiveSupport::Concern

  private

  # DB-PORTABLE: Advisory locks sunt Postgres-only
  # Pe alte DB-uri (SQLite, MySQL), returnăm false și skip-uim lock-ul
  #
  # MULTI-DB SAFETY: Folosim advisory_lock_connection pentru a obține
  # conexiunea corectă (poate fi override în clasa care include concern-ul)
  def supports_pg_advisory_locks?
    !!(advisory_lock_connection.adapter_name =~ /postgres/i)
  end

  # Conexiunea pe care se execută advisory lock-urile.
  # DEFAULT: VariantExternalId.connection (modelul principal pentru mapping-uri)
  # OVERRIDE: În servicii/modele care folosesc altă conexiune, suprascrie această metodă
  #
  # NOTĂ: Folosim VariantExternalId.connection și nu ActiveRecord::Base.connection
  # pentru a fi safe în scenarii multi-db (role switching, sharding, etc.)
  def advisory_lock_connection
    VariantExternalId.connection
  end

  # PORTABLE GUARD: Verifică dacă conexiunea are tranzacție deschisă
  # FALLBACK: Unele adaptere AR (mai vechi, custom, sau multi-DB) pot să nu implementeze
  # `transaction_open?`. În acest caz, fallback la `open_transactions > 0`.
  #
  # NOTĂ: `open_transactions` returnează nivelul de nesting (0 = fără tranzacție),
  # pe când `transaction_open?` e mai precis (ține cont și de savepoints).
  # Preferăm `transaction_open?` când e disponibil, fallback altfel.
  def transaction_open_on?(conn)
    if conn.respond_to?(:transaction_open?)
      conn.transaction_open?
    elsif conn.respond_to?(:open_transactions)
      conn.open_transactions.to_i > 0
    else
      # Dacă nici unul nu e disponibil, presupunem că e OK (să nu blocăm la runtime)
      # dar logăm warning pentru debugging
      Rails.logger.warn(
        "[AdvisoryLockKey] Connection #{conn.class} does not respond to transaction_open? or open_transactions"
      )
      true
    end
  end

  # FAIL-FAST GUARD: Verifică că suntem într-o tranzacție pe conexiunea corectă
  # pg_advisory_xact_lock NECESITĂ o tranzacție deschisă pe aceeași conexiune.
  # Fără tranzacție, lock-ul se eliberează imediat (tranzacție implicită) și NU serializează nimic.
  #
  # Apelează această metodă la începutul oricărui acquire_*_lock pentru a prinde bug-uri
  # de tip "tranzacție pe altă conexiune" instant în dev/test, nu silent fail în prod.
  def assert_transaction_open_on_lock_connection!
    return unless supports_pg_advisory_locks?

    unless transaction_open_on?(advisory_lock_connection)
      # SAFE-NAV: pool/db_config/name pot fi nil în test adapters sau config-uri custom
      # Evităm NoMethodError în timpul construirii mesajului de eroare
      db_name = advisory_lock_connection.pool&.db_config&.name || "unknown"
      raise RuntimeError, <<~MSG.squish
        pg_advisory_xact_lock requires an open transaction on advisory_lock_connection.
        Current connection (#{db_name}) has no open transaction.
        Ensure you call this from within VariantExternalId.transaction { ... } block.
      MSG
    end
  end

  # Convertește CRC32 (unsigned 32-bit) la signed int32 pentru Postgres
  # pg_advisory_xact_lock(int, int) cere int4 semnat (-2^31 .. 2^31-1)
  # CRC32 returnează 0..2^32-1, deci valori >= 2^31 ar da "integer out of range"
  def int32(u)
    u &= 0xffff_ffff
    u >= 0x8000_0000 ? u - 0x1_0000_0000 : u
  end
end
