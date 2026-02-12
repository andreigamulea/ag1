ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors, with: :threads)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    self.fixture_paths = [Rails.root.join("test", "fixtures")]
    # NOTE: fixtures :all a fost eliminat - fiecare test își încarcă ce fixtures are nevoie
    # System tests din suite/ creează datele programatic și nu folosesc fixtures

    # Add more helper methods to be used by all tests here...
  end
end
