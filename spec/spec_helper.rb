require "bundler/setup"
require "pry"
require "action_view"
require "grsx"

module MockComponentHelpers
  def redefine
    _verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = _verbose
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.include MockComponentHelpers

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run_when_matching :focus
end
