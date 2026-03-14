require "rbexy/version"
require "active_support/inflector"

require "rbexy/rails/engine" if defined?(::Rails)

module Rbexy
  autoload :Lexer,          "rbexy/lexer"
  autoload :Parser,         "rbexy/parser"
  autoload :Nodes,          "rbexy/nodes"
  autoload :PhlexRuntime,   "rbexy/phlex_runtime"
  autoload :PhlexCompiler,  "rbexy/phlex_compiler"
  autoload :PhlexComponent, "rbexy/phlex_component"
  autoload :PropInspector,  "rbexy/prop_inspector"
  autoload :Configuration,  "rbexy/configuration"
  autoload :ComponentResolver, "rbexy/component_resolver"
  autoload :Template,       "rbexy/template"

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Compile a .rbx template to Phlex DSL Ruby code.
    # Returns a string that can be class_eval'd inside a PhlexComponent.
    def compile(template)
      tokens = Lexer.new(template, configuration.element_resolver).tokenize
      root   = Parser.new(tokens).parse
      PhlexCompiler.new(root).compile
    end
  end
end
