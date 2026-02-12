require "application_system_test_case"

class ProductVariantDisplayTest < ApplicationSystemTestCase
  setup do
    # Creeaza option types
    @culoare = OptionType.find_or_create_by!(name: "Culoare", presentation: "Culoare")
    @marime = OptionType.find_or_create_by!(name: "Marime", presentation: "Mărime")

    # Option values
    @rosu = @culoare.option_values.find_or_create_by!(name: "Roșu", presentation: "Roșu", position: 1)
    @albastru = @culoare.option_values.find_or_create_by!(name: "Albastru", presentation: "Albastru", position: 2)
    @m = @marime.option_values.find_or_create_by!(name: "M", presentation: "M", position: 1)
    @l = @marime.option_values.find_or_create_by!(name: "L", presentation: "L", position: 2)

    # Creeaza categorii
    @carte = Category.find_or_create_by!(name: "carte", slug: "carte")
    @fizic = Category.find_or_create_by!(name: "fizic", slug: "fizic")

    # Creeaza produs cu variante
    @product = Product.create!(
      name: "Carte Test Variante #{SecureRandom.hex(4)}",
      slug: "carte-test-variante-#{SecureRandom.hex(4)}",
      sku: "TESTVAR-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 100,
      status: "active",
      external_image_url: "https://ayus-cdn.b-cdn.net/product-main.jpg"
    )

    @product.categories << [@carte, @fizic]
    @product.product_option_types.create!(option_type: @culoare)
    @product.product_option_types.create!(option_type: @marime)

    # Varianta 1: Roșu + M
    @variant1 = @product.variants.create!(
      sku: "VAR1-#{SecureRandom.hex(4)}",
      price: 39.99,
      stock: 10,
      vat_rate: 19.0,
      status: 0,
      external_image_url: "https://ayus-cdn.b-cdn.net/variant1-main.jpg",
      external_image_urls: [
        "https://ayus-cdn.b-cdn.net/variant1-gal1.jpg",
        "https://ayus-cdn.b-cdn.net/variant1-gal2.jpg"
      ]
    )
    @variant1.option_values << [@rosu, @m]
    @variant1.save!

    # Varianta 2: Albastru + L
    @variant2 = @product.variants.create!(
      sku: "VAR2-#{SecureRandom.hex(4)}",
      price: 44.99,
      stock: 5,
      vat_rate: 19.0,
      status: 0,
      external_image_url: "https://ayus-cdn.b-cdn.net/variant2-main.jpg",
      external_image_urls: [
        "https://ayus-cdn.b-cdn.net/variant2-gal1.jpg"
      ]
    )
    @variant2.option_values << [@albastru, @l]
    @variant2.save!
  end

  test "afiseaza selectoarele de variante pe pagina produsului" do
    visit carti_path(@product)

    assert_selector ".variant-selector"
    assert_selector "select.variant-option-dropdown", count: 2

    # Verifica ca exista dropdown-urile pentru Culoare si Marime
    assert_text "Culoare:"
    assert_text "Marime:"
  end

  test "selectarea variantei actualizeaza pretul" do
    visit carti_path(@product)

    # Selecteaza Culoare: Roșu (gaseste dropdown-ul pentru Culoare)
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Roșu"

    # Selecteaza Marime: M
    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "M"

    # Verifica ca pretul s-a actualizat la 39.99
    within "#product-price" do
      assert_text "39.99 lei"
    end
  end

  test "selectarea variantei actualizeaza stocul" do
    visit carti_path(@product)

    # Initial ar trebui sa spuna "Selectează opțiunile"
    within "#variant-stock-info" do
      assert_text "Selectează opțiunile"
    end

    # Selecteaza Culoare: Roșu
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Roșu"

    # Selecteaza Marime: M
    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "M"

    # Verifica ca stocul s-a actualizat
    within "#variant-stock-info" do
      assert_text "10 bucăți disponibile"
    end
  end

  test "nu permite adaugarea in cos fara selectare varianta completa" do
    visit carti_path(@product)

    # Butonul ar trebui sa fie disabled initial
    submit_btn = find("#add-to-cart-submit")
    assert submit_btn.disabled?

    # Selecteaza doar Culoare (nu si Marime)
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Roșu"

    # Butonul ar trebui sa fie inca disabled
    assert submit_btn.disabled?
  end

  test "permite adaugarea in cos dupa selectarea completa a variantei" do
    visit carti_path(@product)

    # Selecteaza Culoare: Albastru
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Albastru"

    # Selecteaza Marime: L
    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "L"

    # Butonul ar trebui sa fie enabled
    submit_btn = find("#add-to-cart-submit")
    refute submit_btn.disabled?

    # Click pe butonul de adaugare in cos
    click_button "Adauga in cos"

    # Verifica redirect la pagina cosului
    assert_current_path cart_index_path

    # Verifica ca produsul este in cos cu varianta corecta
    assert_text @product.name
    assert_text "Culoare: Albastru, Marime: L"
    assert_text "44.99 lei"
  end

  test "hidden input pentru variant_id este completat corect" do
    visit carti_path(@product)

    # Selecteaza Culoare: Roșu
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Roșu"

    # Selecteaza Marime: M
    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "M"

    # Verifica ca hidden field-ul are ID-ul variantei corecte
    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal @variant1.id.to_s, hidden_input.value
  end

  test "schimbarea variantei actualizeaza variant_id-ul" do
    visit carti_path(@product)

    # Selecteaza prima varianta
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Roșu"

    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "M"

    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal @variant1.id.to_s, hidden_input.value

    # Schimba la a doua varianta
    culoare_dropdown.select "Albastru"
    marime_dropdown.select "L"

    # Verifica ca s-a actualizat
    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal @variant2.id.to_s, hidden_input.value
  end

  test "varianta fara stoc dezactiveaza butonul de adaugare in cos" do
    # Creeaza o varianta fara stoc
    varianta_epuizata = @product.variants.create!(
      sku: "VAR-EPUIZAT-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 0,
      vat_rate: 19.0,
      status: 0
    )

    # Creeaza option values noi pentru aceasta varianta
    verde = @culoare.option_values.find_or_create_by!(name: "Verde", presentation: "Verde", position: 3)
    xs = @marime.option_values.find_or_create_by!(name: "XS", presentation: "XS", position: 0)

    varianta_epuizata.option_values << [verde, xs]
    varianta_epuizata.save!

    visit carti_path(@product)

    # Selecteaza varianta epuizata
    culoare_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @culoare.id.to_s }
    culoare_dropdown.select "Verde"

    marime_dropdown = all("select.variant-option-dropdown").find { |dd| dd["data-option-type-id"] == @marime.id.to_s }
    marime_dropdown.select "XS"

    # Verifica ca stocul spune "Stoc epuizat"
    within "#variant-stock-info" do
      assert_text "Stoc epuizat"
    end

    # Butonul ar trebui sa fie disabled
    submit_btn = find("#add-to-cart-submit")
    assert submit_btn.disabled?
  end

  test "JSON data contine informatii despre imagini variante" do
    visit carti_path(@product)

    # Cauta script-ul cu variants-data
    variants_json = find("#variants-data", visible: false).text(:all)
    variants = JSON.parse(variants_json)

    # Verifica ca prima varianta are imaginile corecte
    variant1_data = variants.find { |v| v["id"] == @variant1.id }
    assert_equal "https://ayus-cdn.b-cdn.net/variant1-main.jpg", variant1_data["external_image_url"]
    assert_equal 2, variant1_data["external_image_urls"].length
    assert_includes variant1_data["external_image_urls"], "https://ayus-cdn.b-cdn.net/variant1-gal1.jpg"
  end
end
