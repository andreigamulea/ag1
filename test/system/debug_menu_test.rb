require_relative "../application_system_test_case"

class DebugMenuTest < ApplicationSystemTestCase
  self.use_transactional_tests = true

  test "dropdown cont se deschide la click" do
    # Crează user
    user = User.create!(
      email: "debug-#{SecureRandom.hex(4)}@test.com",
      password: "parola123",
      password_confirmation: "parola123",
      active: true,
      role: 0
    )

    # Login
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "user[password]", with: "parola123"
    click_button "Intră în cont"

    # Verifică că suntem logați
    assert_selector "#account-toggle", wait: 5

    # Verifică erori JavaScript din consolă
    js_errors = page.driver.browser.logs.get(:browser).select { |e| e.level == "SEVERE" }
    puts "=== JS ERRORS (before click): #{js_errors.map(&:message).join(', ')}" if js_errors.any?

    # Verifică dacă Stimulus e conectat
    stimulus_connected = page.evaluate_script("document.querySelector('[data-controller=\"header-menu\"]') !== null")
    puts "=== Stimulus controller element exists: #{stimulus_connected}"

    has_target = page.evaluate_script("document.querySelector('[data-header-menu-target=\"accountDropdown\"]') !== null")
    puts "=== accountDropdown target exists: #{has_target}"

    # Verifică starea dropdown-ului ÎNAINTE de click
    show_before = page.evaluate_script("document.getElementById('account-dropdown')?.classList.contains('show')")
    puts "=== Dropdown has 'show' BEFORE click: #{show_before}"

    sleep 2

    # Dump importmap content
    importmap_content = page.evaluate_script("document.querySelector('script[type=\"importmap\"]')?.textContent")
    puts "=== IMPORTMAP CONTENT:"
    puts importmap_content

    # Check all script tags
    scripts_info = page.evaluate_script("
      Array.from(document.querySelectorAll('script')).map(function(s) {
        return s.type + ' | src=' + (s.src || 'inline') + ' | length=' + (s.textContent || '').length
      })
    ")
    puts "=== SCRIPT TAGS:"
    scripts_info.each { |s| puts "  #{s}" }

    # Check Stimulus
    stimulus_app = page.evaluate_script("!!window.Stimulus")
    puts "=== window.Stimulus exists: #{stimulus_app}"

    # Check all JS console output
    js_logs = page.driver.browser.logs.get(:browser)
    puts "=== JS CONSOLE:"
    js_logs.each { |l| puts "  [#{l.level}] #{l.message}" }

    # Check the module script content
    module_content = page.evaluate_script("document.querySelector('script[type=\"module\"]')?.textContent")
    puts "=== MODULE SCRIPT CONTENT: '#{module_content}'"

    # Try loading application.js manually
    app_url = page.evaluate_script("document.querySelector('script[type=\"importmap\"]') && JSON.parse(document.querySelector('script[type=\"importmap\"]').textContent).imports.application")
    puts "=== APPLICATION JS URL: #{app_url}"

    # Fetch it and check status
    fetch_result = page.evaluate_script("
      (async function() {
        try {
          let resp = await fetch('#{app_url}');
          let text = await resp.text();
          return 'status=' + resp.status + ' length=' + text.length + ' first100=' + text.substring(0, 100);
        } catch(e) {
          return 'error: ' + e.message;
        }
      })()
    ")
    sleep 1
    fetch_result = page.evaluate_script("document._fetchResult")
    # Alternative: use synchronous XMLHttpRequest
    app_js_info = page.evaluate_script("
      (function() {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '#{app_url}', false);
        xhr.send();
        return 'status=' + xhr.status + ' length=' + xhr.responseText.length + ' content=' + xhr.responseText.substring(0, 200);
      })()
    ")
    puts "=== APPLICATION JS: #{app_js_info}"

    # Try click
    find("#account-toggle").click
    sleep 0.5
    show_after = page.evaluate_script("document.getElementById('account-dropdown').classList.contains('show')")
    puts "=== Dropdown show after click: #{show_after}"

    assert show_after, "Dropdown should open!"

    # Assert-ul principal
    assert show_after, "Dropdown-ul ar trebui să aibă clasa 'show' după click!"
    assert_selector "#account-dropdown.show"
    assert_text "Logout"
  end
end
