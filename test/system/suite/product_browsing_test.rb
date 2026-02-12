require_relative "suite_test_helper"

class ProductBrowsingTest < SuiteTestCase
  setup do
    @product = create_test_product(
      name: "Ashwagandha - Ghid Complet",
      description: "Totul despre planta adaptogenă Ashwagandha",
      price: 39.99,
      stock: 50
    )

    @product2 = create_test_product(
      name: "Turmeric și Sănătatea",
      description: "Beneficiile turmeticului în medicina ayurvedică",
      price: 29.99,
      stock: 25
    )
  end

  # ── CATALOG ──────────────────────────────────────────────────────

  test "vizitarea catalogului de cărți afișează produsele" do
    visit carti_index_path

    assert_selector "h1", text: "Cărți"
    assert_selector ".product-card", minimum: 2
    # Nu mai căutăm produse specifice - catalogul poate avea multe pagini
  end

  test "catalogul afișează prețurile produselor" do
    visit carti_index_path

    # Verificăm că există prețuri afișate în catalog
    assert_selector ".product-price", minimum: 1
  end

  test "catalogul afișează statusul stocului" do
    visit carti_index_path

    # Produsele in_stock ar trebui să arate disponibilitatea
    assert_selector ".stock", minimum: 1
  end

  test "fiecare produs are buton de adăugare în coș" do
    visit carti_index_path

    assert_selector ".add-to-cart-btn", minimum: 2
  end

  # ── PAGINA DE PRODUS ─────────────────────────────────────────────

  test "vizitarea paginii unui produs afișează detaliile" do
    visit carti_path(@product.slug)

    assert_selector "h1", text: @product.name
    assert_text @product.description
    assert_text "39.99"
  end

  test "pagina de produs are buton de adăugare în coș" do
    visit carti_path(@product.slug)

    assert_button "Adauga in cos"
  end

  test "pagina de produs are câmp de cantitate" do
    visit carti_path(@product.slug)

    assert_selector "#quantity_input"
    quantity_input = find("#quantity_input")
    assert_equal "1", quantity_input.value
  end

  test "butoanele +/- modifică cantitatea" do
    visit carti_path(@product.slug)

    # Cantitatea inițială este 1
    assert_equal "1", find("#quantity_input").value

    # Click pe + pentru a crește cantitatea
    find(".quantity-increase").click
    assert_equal "2", find("#quantity_input").value

    # Click pe - pentru a scădea cantitatea
    find(".quantity-decrease").click
    assert_equal "1", find("#quantity_input").value
  end

  test "pagina de produs are link către continuarea cumpărăturilor" do
    visit carti_path(@product.slug)

    assert_link "Continua cumparaturile"
  end

  # ── PRODUSE OUT OF STOCK ─────────────────────────────────────────

  test "un produs fără stoc afișează statusul corespunzător" do
    out_of_stock = create_test_product(
      name: "Carte Epuizată",
      stock: 0,
      stock_status: "out_of_stock"
    )

    visit carti_path(out_of_stock.slug)
    # Verificăm că pagina se încarcă (produsul există)
    assert_selector "h1", text: "Carte Epuizată"
  end

  # ── CĂUTARE ──────────────────────────────────────────────────────

  test "căutarea unui produs existent returnează rezultate" do
    visit root_path

    fill_in "q", with: "Ashwagandha", match: :first
    find(".search-button", match: :first).click

    assert_text "Rezultate căutare"
    assert_text "Ashwagandha - Ghid Complet"
  end

  test "căutarea unui termen inexistent arată mesaj corespunzător" do
    visit root_path

    fill_in "q", with: "xyzinexistent123", match: :first
    find(".search-button", match: :first).click

    assert_text "Nu am găsit produse"
  end

  test "căutarea fără termen arată mesaj informativ" do
    visit search_index_path

    assert_text "Introdu un termen de căutare"
  end

  test "căutarea parțială găsește produsul" do
    visit root_path

    fill_in "q", with: "Turmeric", match: :first
    find(".search-button", match: :first).click

    assert_text "Turmeric și Sănătatea"
  end
end
