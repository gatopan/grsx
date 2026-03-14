require_relative 'lib/grsx/version'

Gem::Specification.new do |spec|
  spec.name          = "grsx"
  spec.version       = Grsx::VERSION
  spec.authors       = ["Gatopan"]
  spec.email         = ["dev@gatopan.com"]

  spec.summary       = "GRSX — JSX-flavored templates for Ruby, powered by Phlex"
  spec.homepage      = "https://github.com/gatopan/grsx"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/gatopan/grsx"

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime
  spec.add_dependency "activesupport", ">= 7.1"
  spec.add_dependency "phlex",         "~> 2.0"
  spec.add_dependency "phlex-rails",   "~> 2.0"

  # Development / test
  spec.add_development_dependency "appraisal", "~> 2.2"
  spec.add_development_dependency "rails", ">= 7.1"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-rails", "~> 6.0", ">= 6.0.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "mutex_m"
  spec.add_development_dependency "logger"
  spec.add_development_dependency "bigdecimal"
  spec.add_development_dependency "drb"
  spec.add_development_dependency "benchmark"
  spec.add_development_dependency "base64"
end
