require "bundler/setup"
require "pry"
# Required by phlex-rails (depends on ActiveSupport::SafeBuffer)
require "action_view"
require "grsx"

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run_when_matching :focus
end
