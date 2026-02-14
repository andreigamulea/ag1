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

    # Culoare = primary, Marime = secondary
    @product.product_option_types.create!(option_type: @culoare, primary: true, position: 0)
    @product.product_option_types.create!(option_type: @marime, primary: false, position: 1)

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

  test "afiseaza swatches pentru optiunea principala si butoane pentru secundara" do
    visit carti_path(@product)

    assert_selector ".variant-selector"

    # Swatches pentru Culoare (primary)
    assert_selector ".variant-swatches"
    assert_selector ".variant-swatch", count: 2
    assert_text "Culoare:"

    # Butoane pentru Marime (secondary)
    assert_selector ".variant-buttons"
    assert_selector ".variant-btn", count: 2
    assert_text "Mărime:"
  end

  test "swatches au buline colorate pentru optiunea Culoare" do
    visit carti_path(@product)

    # Fiecare swatch ar trebui sa aiba o bulina colorata
    within ".variant-swatches" do
      circles = all(".swatch-color")
      assert_equal 2, circles.length
    end
  end

  test "click pe swatch schimba varianta si actualizeaza pretul" do
    visit carti_path(@product)

    # Initial: prima varianta selectata (Roșu + M, 39.99)
    within "#product-price" do
      assert_text "39.99 lei"
    end

    # Click pe swatch Albastru
    find(".variant-swatch[data-option-value-id='#{@albastru.id}']").click

    # Auto-selecteaza L (singurul secondary disponibil pentru Albastru)
    # Pretul se actualizeaza la 44.99
    within "#product-price" do
      assert_text "44.99 lei"
    end
  end

  test "click pe swatch actualizeaza stocul" do
    visit carti_path(@product)

    # Initial: prima varianta (Roșu + M, stock = 10)
    within "#variant-stock-info" do
      assert_text "10 bucăți disponibile"
    end

    # Click pe swatch Albastru → varianta Albastru + L (stock = 5)
    find(".variant-swatch[data-option-value-id='#{@albastru.id}']").click

    within "#variant-stock-info" do
      assert_text "5 bucăți disponibile"
    end
  end

  test "click pe buton secondary selecteaza varianta corecta" do
    visit carti_path(@product)

    # Adaugam o varianta Roșu + L pentru a avea optiuni secondary multiple
    variant3 = @product.variants.create!(
      sku: "VAR3-#{SecureRandom.hex(4)}",
      price: 42.00,
      stock: 7,
      vat_rate: 19.0,
      status: 0,
      external_image_url: "https://ayus-cdn.b-cdn.net/variant3-main.jpg"
    )
    variant3.option_values << [@rosu, @l]
    variant3.save!

    visit carti_path(@product)

    # Prima: swatch Roșu activ, buton M auto-selectat (prima varianta)
    # Click pe buton L
    find(".variant-btn[data-option-value-id='#{@l.id}']").click

    # Acum ar trebui sa fie varianta Roșu + L (42.00)
    within "#product-price" do
      assert_text "42.00 lei"
    end

    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal variant3.id.to_s, hidden_input.value
  end

  test "permite adaugarea in cos dupa selectarea variantei" do
    visit carti_path(@product)

    # Initial: prima varianta auto-selectata (Roșu + M)
    submit_btn = find("#add-to-cart-submit")
    refute submit_btn.disabled?

    # Click pe butonul de adaugare in cos
    click_button "Adauga in cos"

    # Verifica redirect la pagina cosului
    assert_current_path cart_index_path

    # Verifica ca produsul este in cos cu varianta corecta
    assert_text @product.name
    assert_text "Culoare: Roșu, Marime: M"
    assert_text "39.99 lei"
  end

  test "hidden input pentru variant_id este completat corect" do
    visit carti_path(@product)

    # Initial: prima varianta auto-selectata
    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal @variant1.id.to_s, hidden_input.value

    # Click pe swatch Albastru → se schimba la variant2
    find(".variant-swatch[data-option-value-id='#{@albastru.id}']").click

    hidden_input = find("#selected-variant-id", visible: false)
    assert_equal @variant2.id.to_s, hidden_input.value
  end

  test "varianta fara stoc dezactiveaza butonul de adaugare in cos" do
    # Creeaza o varianta fara stoc
    verde = @culoare.option_values.find_or_create_by!(name: "Verde", presentation: "Verde", position: 3)
    xs = @marime.option_values.find_or_create_by!(name: "XS", presentation: "XS", position: 0)

    varianta_epuizata = @product.variants.create!(
      sku: "VAR-EPUIZAT-#{SecureRandom.hex(4)}",
      price: 49.99,
      stock: 0,
      vat_rate: 19.0,
      status: 0
    )
    varianta_epuizata.option_values << [verde, xs]
    varianta_epuizata.save!

    visit carti_path(@product)

    # Click pe swatch Verde
    find(".variant-swatch[data-option-value-id='#{verde.id}']").click

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

  test "swatch-ul activ are clasa variant-swatch--active" do
    visit carti_path(@product)

    # Initial: primul swatch activ
    active_swatches = all(".variant-swatch--active")
    assert_equal 1, active_swatches.length

    # Click pe al doilea swatch
    find(".variant-swatch[data-option-value-id='#{@albastru.id}']").click

    # Doar un swatch activ
    active_swatches = all(".variant-swatch--active")
    assert_equal 1, active_swatches.length

    # Al doilea swatch e cel activ
    assert_selector ".variant-swatch--active[data-option-value-id='#{@albastru.id}']"
  end

  test "butonul secondary activ are clasa variant-btn--active" do
    # Adaugam varianta Roșu + L pentru a avea optiuni secondary
    variant3 = @product.variants.create!(
      sku: "VAR3B-#{SecureRandom.hex(4)}",
      price: 41.00,
      stock: 3,
      vat_rate: 19.0,
      status: 0
    )
    variant3.option_values << [@rosu, @l]
    variant3.save!

    visit carti_path(@product)

    # Initial: M auto-selectat
    assert_selector ".variant-btn--active[data-option-value-id='#{@m.id}']"

    # Click pe L
    find(".variant-btn[data-option-value-id='#{@l.id}']").click

    # L activ, M nu mai e activ
    assert_selector ".variant-btn--active[data-option-value-id='#{@l.id}']"
    assert_no_selector ".variant-btn--active[data-option-value-id='#{@m.id}']"
  end
end
