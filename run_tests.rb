#!/usr/bin/env ruby

require 'fileutils'
require 'minitest'
require 'minitest/reporters'

# Setup Minitest reporters
Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

# Load the test file
ENV['RAILS_ENV'] = 'test'
require File.expand_path('../config/environment', __FILE__)

# Run tests
Dir.glob('test/models/product_adding_test.rb').each { |f| require f }

# Output results
puts "\n\n======== TEST RESULTS ========"
Minitest.run
