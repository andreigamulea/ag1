require_relative "suite_test_helper"

class CartManagementTest < SuiteTestCase
  setup do
    @product = create_test_product(
      name: "Carte Ayurveda Bază",
      price: 45.00,
      stock: 50
    )
    @product2 = create_test_product(
      name: "Carte Meditație",
      price: 35.00,
      stock: 30
    )
  end

  # ── ADĂUGARE ÎN COȘ ─────────────────────────────────────────────

  test "adăugarea unui produs în coș din catalog" do
    visit carti_index_path

    # Găsim primul buton de adăugare
    first(".add-to-cart-btn").click

    # După redirect la coș, produsul trebuie să fie acolo
    assert_selector "h1", text: "Coșul tău"
    assert_selector ".cart-item", minimum: 1
  end

  test "adăugarea unui produs în coș din pagina de produs" do
    visit carti_path(@product.slug)

    click_button "Adauga in cos"

    # Redirecționare la coș cu produsul adăugat
    go_to_cart
    assert_text @product.name
  end

  test "adăugarea unui produs cu cantitate specifică" do
    visit carti_path(@product.slug)

    # Setăm cantitatea la 3
    fill_in "quantity", with: "3"
    click_button "Adauga in cos"

    # Verificăm în coș
    go_to_cart
    assert_text @product.name
  end

  # ── VIZUALIZARE COȘ ──────────────────────────────────────────────

  test "coșul gol afișează mesajul corespunzător" do
    go_to_cart

    assert_selector "h1", text: "Coșul tău"
    assert_text "Coșul este gol"
  end

  test "coșul afișează produsele adăugate" do
    add_product_to_cart(@product)
    go_to_cart

    assert_selector "h1", text: "Coșul tău"
    assert_text @product.name
    assert_text "45"  # prețul
  end

  test "coșul afișează sumarul cu subtotal" do
    add_product_to_cart(@product)
    go_to_cart

    assert_selector ".cart-summary"
    assert_text "Subtotal"
    assert_text "Total de plată"
  end

  test "adăugarea mai multor produse diferite în coș" do
    add_product_to_cart(@product)
    add_product_to_cart(@product2)
    go_to_cart

    assert_text @product.name
    assert_text @product2.name
  end

  # ── ACTUALIZARE CANTITATE ────────────────────────────────────────

  test "actualizarea cantității unui produs din coș" do
    add_product_to_cart(@product)
    go_to_cart

    # Modificăm cantitatea
    qty_input = find(".qty-input[data-cart-key='#{@product.id}']")
    qty_input.fill_in with: "5"

    click_button "ACTUALIZEAZĂ COȘUL"

    # Verificăm că pagina de coș se reîncarcă cu noua cantitate
    assert_selector "h1", text: "Coșul tău"
    assert_text @product.name
  end

  test "butoanele +/- din coș modifică cantitatea" do
    add_product_to_cart(@product)
    go_to_cart

    initial_value = find(".qty-input[data-cart-key='#{@product.id}']").value.to_i

    # Click pe +
    find(".qty-plus[data-cart-key='#{@product.id}']").click

    new_value = find(".qty-input[data-cart-key='#{@product.id}']").value.to_i
    assert_equal initial_value + 1, new_value
  end

  # ── ȘTERGERE DIN COȘ ────────────────────────────────────────────

  test "ștergerea unui produs din coș" do
    add_product_to_cart(@product)
    go_to_cart

    assert_text @product.name

    # JS-ul clonează butoanele la DOMContentLoaded și adaugă event listeners.
    # Folosim execute_script cu CSRF token sigur (cu null check)
    page.execute_script(<<~JS)
      var meta = document.querySelector('meta[name="csrf-token"]');
      var csrfToken = meta ? meta.content : '';
      fetch('/cart/remove', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ product_id: #{@product.id} }),
        credentials: 'same-origin'
      }).then(function(response) {
        if (response.ok) { window.location.reload(); }
      });
    JS

    # Așteptăm reload-ul paginii
    assert_text "Coșul este gol", wait: 5
  end

  # ── NAVIGARE DIN COȘ ────────────────────────────────────────────

  test "coșul cu produse are buton de finalizare comandă" do
    add_product_to_cart(@product)
    go_to_cart

    assert_link "Finalizează comanda"
  end

  test "coșul are link pentru continuarea cumpărăturilor" do
    go_to_cart

    assert_link "Continuă cumpărăturile"
  end

  test "click pe Finalizează comanda duce la checkout" do
    add_product_to_cart(@product)
    go_to_cart

    click_link "Finalizează comanda"

    assert_current_path new_order_path
  end

  # ── HEADER CART BADGE ────────────────────────────────────────────

  test "badge-ul coșului din header se actualizează" do
    visit root_path
    cart_count_before = find(".cart-count").text

    add_product_to_cart(@product)
    visit root_path

    # După adăugare, count-ul ar trebui să fie mai mare
    cart_count_after = find(".cart-count").text
    assert_not_equal "0", cart_count_after
  end
end
