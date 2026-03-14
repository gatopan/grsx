require "rbexy/version"
require "active_support/inflector"
require "active_support/concern"
require "active_support/core_ext/enumerable"
require "action_view"
require "ostruct"

require "rbexy/rails/engine" if defined?(::Rails)

module Rbexy
  autoload :Lexer, "rbexy/lexer"
  autoload :Parser, "rbexy/parser"
  autoload :Nodes, "rbexy/nodes"
  autoload :Runtime, "rbexy/runtime"
  autoload :PhlexRuntime, "rbexy/phlex_runtime"
  autoload :PhlexCompiler, "rbexy/phlex_compiler"
  autoload :PhlexComponent, "rbexy/phlex_component"
  autoload :ComponentContext, "rbexy/component_context"
  autoload :Configuration, "rbexy/configuration"
  autoload :ComponentResolver, "rbexy/component_resolver"
  autoload :Template, "rbexy/template"
  autoload :Refinements, "rbexy/refinements"
  autoload :ASTTransformer, "rbexy/ast_transformer"

  ContextNotFound = Class.new(StandardError)

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def compile(template, context = build_default_compile_context(template))
      tokens = Lexer.new(template, context.element_resolver).tokenize
      root = Parser.new(tokens).parse
      root.inject_compile_context(context)
      root.transform!
      root.precompile.compile
    end

    # Compile a .rbx template to Phlex DSL method call code.
    # Returns a Ruby code string that can be evaluated inside a PhlexRuntime.
    #
    # Example:
    #   code = Rbexy.phlex_compile(Template.new(source))
    #   runtime = Rbexy::PhlexRuntime.new(view_context: ctx, assigns: assigns)
    #   html = runtime.call { runtime.instance_eval(code) }
    def phlex_compile(template, context = build_default_compile_context(template))
      tokens = Lexer.new(template, context.element_resolver).tokenize
      root = Parser.new(tokens).parse
      root.inject_compile_context(context)
      root.transform!
      PhlexCompiler.new(root).compile
    end

    def evaluate(template_string, runtime = Rbexy::Runtime.new)
      runtime.evaluate compile(Template.new(template_string))
    end

    def build_default_compile_context(template)
      OpenStruct.new(
        template: template,
        element_resolver: configuration.element_resolver,
        ast_transformer: configuration.transforms
      )
    end
  end
end
