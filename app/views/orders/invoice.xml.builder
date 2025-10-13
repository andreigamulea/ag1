# app/views/orders/invoice.xml.builder
xml.instruct! :xml, :version => "1.0", :encoding => "UTF-8"

xml.Facturi do
  xml.Factura do
    xml.Antet do
      # Furnizor details - hardcoded based on example; adjust as needed
      xml.FurnizorNume "AYUS GRUP SRL"  # Replace with actual supplier name
      xml.FurnizorCIF "15768237"  # Replace with actual CIF
      xml.FurnizorNrRegCom "J40/12819/2003"  # Replace with actual reg com
      xml.FurnizorCapital "200 Lei"  # Replace with actual capital
      xml.FurnizorTara ""  # Replace if needed
      xml.FurnizorJudet ""  # Replace if needed
      xml.FurnizorAdresa "Municipiul Bucuresti, Sector 5, Intr. Ferentari, Nr.72, Bl.4b, Sc.D, Et.3, Ap.32"  # Replace with actual address
      xml.FurnizorBanca "ING BANK"  # Replace with actual bank
      xml.FurnizorIBAN "RO86INGB0000999902964556"  # Replace with actual IBAN
      xml.FurnizorInformatiiSuplimentare ""

      # Client details from @order
      xml.ClientNume "#{@order.first_name} #{@order.last_name}"
      xml.ClientInformatiiSuplimentare @order.company_name.presence || ""
      xml.ClientCIF @order.cui.presence || "0000000000000"
      xml.ClientNrRegCom ""
      
      # Determine ClientTara
      country_name = @order.country.presence || "Romania"
      tara = Tari.find_by("LOWER(nume) = ?", country_name.downcase)
      client_tara = if tara && country_name.downcase != "romania"
        tara.abr.presence || country_name
      else
        "Romania"
      end
      xml.ClientTara client_tara
      
      # Determine ClientJudet
      if client_tara == "Romania"
        judet = Judet.find_by("LOWER(denjud) = ?", @order.county.downcase)
        client_judet = judet ? judet.cod : ""
      else
        client_judet = "B"
      end
      xml.ClientJudet client_judet
      
      # Determine ClientAdresa
      client_adresa = [@order.street, @order.street_number].compact.join(" ").strip
      xml.ClientAdresa client_adresa
      
      xml.ClientBanca ""
      xml.ClientIBAN ""
      xml.ClientTelefon ""
      xml.ClientMail ""

      # Factura details from @invoice and @order
      xml.FacturaNumar "AYG#{@invoice.invoice_number}"
      xml.FacturaData @invoice.emitted_at.strftime("%d.%m.%Y") if @invoice.emitted_at
      xml.FacturaScadenta @invoice.due_date.strftime("%d.%m.%Y") if @invoice.due_date
      xml.FacturaTaxareInversa "Nu"
      xml.FacturaTVAIncasare "Nu"
      xml.FacturaTip ""
      xml.FacturaInformatiiSuplimentare ""
      xml.FacturaMoneda @invoice.currency.presence || "RON"
      xml.FacturaCotaTVA ""  # Global VAT rate if applicable; left empty as per example
      xml.FacturaID ""
      xml.FacturaGreutate ""
    end

    xml.Detalii do
      xml.Continut do
        @order.order_items.each_with_index do |item, index|
          xml.Linie do
            xml.LinieNrCrt (index + 1).to_s
            xml.Descriere item.product_name
            xml.UM "buc"  # Assuming 'buc' as unit; adjust if needed
            xml.Cantitate sprintf("%.2f", item.quantity)
            xml.Pret sprintf("%.2f", item.price)  # Unit price
            xml.Valoare sprintf("%.2f", item.total_price)  # Total value (price * quantity)
            xml.CotaTVA item.vat.to_i.to_s  # VAT code/rate
            xml.ProcTVA item.vat.to_i.to_s  # VAT percentage
            xml.TVA sprintf("%.2f", (item.total_price * item.vat.to_f / (100 + item.vat.to_f)))  # VAT amount, assuming price is gross
          end
        end
      end
    end

    xml.Sumar do
      subtotal = @order.order_items.where.not(product_name: ["Discount", "Transport"]).sum(:total_price)
      discount = @order.order_items.find_by(product_name: "Discount")&.total_price || 0
      transport = @order.order_items.find_by(product_name: "Transport")&.total_price || 0
      total_net = subtotal + discount + transport  # Adjust if prices are gross/net
      total_tva = @order.vat_amount  # From order
      total_valoare = @order.total

      xml.Total sprintf("%.2f", total_net)
      xml.TotalTVA sprintf("%.2f", total_tva)
      xml.TotalValoare sprintf("%.2f", total_valoare)
    end

    xml.Observatii do
      xml.txtObservatii "Comanda online #{@order.id}"  # Or @order.notes if preferred
    end
  end
end