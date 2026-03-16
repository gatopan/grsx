# frozen_string_literal: true

require "grsx/version"
require "active_support/inflector"

require "grsx/rails/engine" if defined?(::Rails)

module Grsx
  autoload :Elements,          "grsx/elements"
  autoload :AST,               "grsx/ast"
  autoload :Parser,            "grsx/parser"
  autoload :Codegen,           "grsx/codegen"
  autoload :RsxDSL,            "grsx/rsx_dsl"
  autoload :PhlexRuntime,      "grsx/phlex_runtime"
  autoload :Preprocessor,      "grsx/preprocessor"
  autoload :PrismCompiler,     "grsx/prism_compiler"
  autoload :ExtendedParser,    "grsx/extended_parser"
  autoload :PhlexComponent,    "grsx/phlex_component"
  autoload :PropInspector,     "grsx/prop_inspector"
  autoload :Configuration,     "grsx/configuration"
  autoload :ComponentResolver, "grsx/component_resolver"
  autoload :TemplateHandler,   "grsx/template_handler"

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Compile .rsx source (Ruby with <Tag> extensions) to Phlex DSL Ruby code.
    # Returns a string that can be class_eval'd inside a PhlexComponent.
    #
    # Options:
    #   source_map: true — emit `# line N` pragmas for RSX→error tracing
    def compile(source, source_map: false)
      Preprocessor.new(resolver: configuration.element_resolver)
        .preprocess(source, source_map: source_map)
    end
  end
end
