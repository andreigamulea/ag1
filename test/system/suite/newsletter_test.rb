require_relative "suite_test_helper"

class NewsletterFlowTest < SuiteTestCase
  # ── ABONARE NEWSLETTER ───────────────────────────────────────────

  test "formularul de newsletter este prezent pe pagină" do
    visit root_path

    assert_selector "#newsletter-form"
    assert_selector "#newsletter_name"
    assert_selector "#newsletter_email"
  end

  test "abonarea la newsletter cu date valide" do
    visit root_path

    within "#newsletter-form" do
      fill_in "newsletter_name", with: "Ion Popescu"
      fill_in "newsletter_email", with: "ion.popescu.newsletter@example.com"
      click_button "Trimite"
    end

    # Verificăm că formularul a fost procesat fără erori de server
    assert_no_text "Internal Server Error"
  end

  test "câmpurile newsletter au atributul required" do
    visit root_path

    name_field = find("#newsletter_name")
    email_field = find("#newsletter_email")

    assert name_field[:required]
    assert email_field[:required]
  end

  # ── PAGINA DEDICATĂ NEWSLETTER ───────────────────────────────────

  test "pagina dedicată de newsletter se încarcă" do
    visit newsletter_path

    # Pagina ar trebui să se încarce fără erori
    assert_no_text "500"
    assert_no_text "Internal Server Error"
  end
end
