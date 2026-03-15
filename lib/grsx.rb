# frozen_string_literal: true

require "grsx/version"
require "active_support/inflector"

require "grsx/rails/engine" if defined?(::Rails)

module Grsx
  autoload :Lexer,          "grsx/lexer"
  autoload :Parser,         "grsx/parser"
  autoload :Nodes,          "grsx/nodes"
  autoload :RsxDSL,         "grsx/rsx_dsl"
  autoload :PhlexRuntime,   "grsx/phlex_runtime"
  autoload :PhlexCompiler,  "grsx/phlex_compiler"
  autoload :PhlexComponent, "grsx/phlex_component"
  autoload :PropInspector,  "grsx/prop_inspector"
  autoload :Configuration,  "grsx/configuration"
  autoload :ComponentResolver, "grsx/component_resolver"
  autoload :Template,       "grsx/template"

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Compile a .rsx template to Phlex DSL Ruby code.
    # Returns a string that can be class_eval'd inside a PhlexComponent.
    def compile(template)
      tokens = Lexer.new(template, configuration.element_resolver).tokenize
      root   = Parser.new(tokens).parse
      PhlexCompiler.new(root).compile
    end
  end
end
