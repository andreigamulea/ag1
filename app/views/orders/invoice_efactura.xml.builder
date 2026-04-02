# app/views/orders/invoice_efactura.xml.builder
# Format UBL 2.1 CIUS-RO compatibil cu e-Factura ANAF

vat_category = ->(rate) { rate.to_i > 0 ? "S" : "E" }

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.Invoice(
  "xmlns" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
  "xmlns:cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
  "xmlns:cbc" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
) do

  xml.cbc :CustomizationID, "urn:cen.eu:en16931:2017#compliant#urn:efactura.mfinante.ro:CIUS-RO:1.0.1"
  xml.cbc :ID, "AYG#{invoice.invoice_number}"
  xml.cbc :IssueDate, invoice.emitted_at.strftime("%Y-%m-%d")
  xml.cbc :DueDate, invoice.due_date.strftime("%Y-%m-%d") if invoice.due_date
  xml.cbc :InvoiceTypeCode, "380"
  xml.cbc :DocumentCurrencyCode, invoice.currency.presence || "RON"

  # Furnizor
  xml.cac :AccountingSupplierParty do
    xml.cac :Party do
      xml.cac :PartyName do
        xml.cbc :Name, "AYUS GRUP SRL"
      end
      xml.cac :PostalAddress do
        xml.cbc :StreetName, "Intr. Ferentari, Nr.72, Bl.4b, Sc.D, Et.3, Ap.32"
        xml.cbc :CityName, "SECTOR5"
        xml.cbc :PostalZone, "051562"
        xml.cbc :CountrySubentity, "RO-B"
        xml.cac :Country do
          xml.cbc :IdentificationCode, "RO"
        end
      end
      xml.cac :PartyTaxScheme do
        xml.cbc :CompanyID, "RO15768237"
        xml.cac :TaxScheme do
          xml.cbc :ID, "VAT"
        end
      end
      xml.cac :PartyLegalEntity do
        xml.cbc :RegistrationName, "AYUS GRUP SRL"
        xml.cbc :CompanyID, "J40/12819/2003"
      end
      xml.cac :Contact do
        xml.cbc :Telephone, ""
        xml.cbc :ElectronicMail, "contact@ayus.ro"
      end
    end
  end

  # Client
  xml.cac :AccountingCustomerParty do
    xml.cac :Party do
      xml.cac :PartyName do
        xml.cbc :Name, order.company_name.presence || "#{order.first_name} #{order.last_name}"
      end
      xml.cac :PostalAddress do
        xml.cbc :StreetName, [order.street, order.street_number].compact.join(" ").strip
        # CityName
        xml.cbc :CityName, order.city.presence || ""
        xml.cbc :PostalZone, order.postal_code.presence || ""
        # CountrySubentity
        if order.country.blank? || order.country.downcase == "romania"
          judet = Judet.find_by("LOWER(denjud) = ?", order.county.to_s.downcase)
          xml.cbc :CountrySubentity, judet ? "RO-#{judet.cod}" : ""
        end
        xml.cac :Country do
          xml.cbc :IdentificationCode, "RO"
        end
      end
      # PartyTaxScheme — doar dacă e PJ cu CUI
      if order.cui.present? && order.cui != "0000000000000"
        xml.cac :PartyTaxScheme do
          cui_val = order.cui.to_s.start_with?("RO") ? order.cui : "RO#{order.cui}"
          xml.cbc :CompanyID, cui_val
          xml.cac :TaxScheme do
            xml.cbc :ID, "VAT"
          end
        end
      end
      xml.cac :PartyLegalEntity do
        xml.cbc :RegistrationName, order.company_name.presence || "#{order.first_name} #{order.last_name}"
      end
      xml.cac :Contact do
        xml.cbc :Telephone, order.phone.presence || ""
        xml.cbc :ElectronicMail, order.email
      end
    end
  end

  # PaymentMeans — card bancar
  xml.cac :PaymentMeans do
    xml.cbc :PaymentMeansCode, "48"
  end

  # Discount global (dacă există)
  discount_item = order.order_items.find_by(product_name: "Discount")
  if discount_item
    discount_abs = discount_item.total_price.abs
    xml.cac :AllowanceCharge do
      xml.cbc :ChargeIndicator, "false"
      xml.cbc :AllowanceChargeReason, "Discount cupon"
      xml.cbc :Amount, sprintf("%.2f", discount_abs), currencyID: (invoice.currency.presence || "RON")
      xml.cac :TaxCategory do
        xml.cbc :ID, "E"
        xml.cbc :Percent, "0"
        xml.cbc :TaxExemptionReason, "Scutit de TVA"
        xml.cac :TaxScheme do
          xml.cbc :ID, "VAT"
        end
      end
    end
  end

  # Grupare TVA
  product_items = order.order_items.where.not(product_name: ["Discount"])
  vat_groups = product_items.group_by { |item| item.vat.to_f }.transform_values do |items|
    taxable = items.sum(&:total_price)
    vat_amount = items.sum { |i| i.total_price * i.vat.to_f / (100 + i.vat.to_f) }
    { taxable: taxable, vat: vat_amount }
  end

  total_vat = vat_groups.values.sum { |v| v[:vat] }

  xml.cac :TaxTotal do
    xml.cbc :TaxAmount, sprintf("%.2f", total_vat), currencyID: (invoice.currency.presence || "RON")
    vat_groups.each do |rate, amounts|
      cat_id = vat_category.call(rate)
      xml.cac :TaxSubtotal do
        xml.cbc :TaxableAmount, sprintf("%.2f", amounts[:taxable] - amounts[:vat]), currencyID: (invoice.currency.presence || "RON")
        xml.cbc :TaxAmount, sprintf("%.2f", amounts[:vat]), currencyID: (invoice.currency.presence || "RON")
        xml.cac :TaxCategory do
          xml.cbc :ID, cat_id
          xml.cbc :Percent, rate.to_i.to_s
          if cat_id == "E"
            xml.cbc :TaxExemptionReason, "Scutit de TVA"
          end
          xml.cac :TaxScheme do
            xml.cbc :ID, "VAT"
          end
        end
      end
    end
  end

  # LegalMonetaryTotal
  subtotal_brut = product_items.sum(&:total_price)
  subtotal_net = subtotal_brut - vat_groups.values.sum { |v| v[:vat] }
  discount_val = discount_item ? discount_item.total_price.abs : 0
  total_val = order.total.to_f

  xml.cac :LegalMonetaryTotal do
    xml.cbc :LineExtensionAmount, sprintf("%.2f", subtotal_net), currencyID: (invoice.currency.presence || "RON")
    xml.cbc :TaxExclusiveAmount, sprintf("%.2f", subtotal_net - discount_val), currencyID: (invoice.currency.presence || "RON")
    xml.cbc :TaxInclusiveAmount, sprintf("%.2f", total_val), currencyID: (invoice.currency.presence || "RON")
    xml.cbc :AllowanceTotalAmount, sprintf("%.2f", discount_val), currencyID: (invoice.currency.presence || "RON") if discount_val > 0
    xml.cbc :PayableAmount, sprintf("%.2f", total_val), currencyID: (invoice.currency.presence || "RON")
  end

  # InvoiceLine — linii produse + transport
  line_items = order.order_items.where.not(product_name: "Discount")
  line_items.each_with_index do |item, index|
    xml.cac :InvoiceLine do
      xml.cbc :ID, (index + 1).to_s
      xml.cbc :InvoicedQuantity, item.quantity.to_s, unitCode: "EA"
      net_price = item.price.to_f / (1 + item.vat.to_f / 100)
      line_net = net_price * item.quantity
      xml.cbc :LineExtensionAmount, sprintf("%.2f", line_net), currencyID: (invoice.currency.presence || "RON")
      xml.cac :Item do
        xml.cbc :Name, [item.product_name, item.variant_options_text.presence].compact.join(" - ")
        xml.cac :ClassifiedTaxCategory do
          cat_id = vat_category.call(item.vat.to_f)
          xml.cbc :ID, cat_id
          xml.cbc :Percent, item.vat.to_i.to_s
          if cat_id == "E"
            xml.cbc :TaxExemptionReason, "Scutit de TVA"
          end
          xml.cac :TaxScheme do
            xml.cbc :ID, "VAT"
          end
        end
      end
      xml.cac :Price do
        xml.cbc :PriceAmount, sprintf("%.2f", net_price), currencyID: (invoice.currency.presence || "RON")
      end
    end
  end
end
