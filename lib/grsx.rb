# frozen_string_literal: true

require "grsx/version"
require "active_support/inflector"

require "grsx/rails/engine" if defined?(::Rails)

module Grsx
  # Raised when the parser detects invalid RSX syntax.
  # Carries the source line number for actionable error messages.
  class SyntaxError < ::SyntaxError
    attr_reader :rsx_line, :rsx_source

    def initialize(message, line: nil, source: nil)
      @rsx_line = line
      @rsx_source = source
      loc = line ? " (line #{line})" : ""
      context = source_context
      full_message = "#{message}#{loc}"
      full_message += "\n#{context}" if context
      super(full_message)
    end

    def source_context
      return nil unless @rsx_line && @rsx_source

      lines = @rsx_source.lines
      return nil if @rsx_line < 1 || @rsx_line > lines.length

      context_lines = []
      start = [@rsx_line - 2, 0].max
      finish = [@rsx_line - 1, lines.length - 1].min

      (start..finish).each do |i|
        prefix = i == @rsx_line - 1 ? ">" : " "
        context_lines << "#{prefix} #{i + 1} | #{lines[i].chomp}"
      end

      context_lines.join("\n")
    end
  end
  autoload :Elements,          "grsx/elements"
  autoload :AST,               "grsx/ast"
  autoload :Parser,            "grsx/parser"
  autoload :Codegen,           "grsx/codegen"
  autoload :RsxDSL,            "grsx/rsx_dsl"
  autoload :PhlexRuntime,      "grsx/phlex_runtime"
  autoload :ExtendedParser,    "grsx/extended_parser"
  autoload :PhlexComponent,    "grsx/phlex_component"
  autoload :TemplateHandler,   "grsx/template_handler"
  autoload :Lint,              "grsx/lint"
  autoload :CLI,               "grsx/cli"

  # ── Configuration ────────────────────────────────────────────────

  class Configuration
    attr_reader :component_namespaces

    def initialize
      self.component_namespaces = {}
    end

    def component_namespaces=(hash)
      @component_namespaces = hash.transform_keys(&:to_s)
    end
  end

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def resolver
      configuration
    end

    # Compile .rsx source (Ruby with <Tag> extensions) to Phlex DSL Ruby code.
    #
    # The output is line-aligned: compiled line N = RSX source line N.
    # This enables accurate error backtraces when used with class_eval
    # or instance_eval's (file, line) arguments.
    def compile(source, resolver: nil)
      r = resolver || self.resolver
      ast = Parser.new(source, resolver: r).parse
      Codegen.new(ast, resolver: r).generate
    end
  end
end
