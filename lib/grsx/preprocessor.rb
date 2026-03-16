# frozen_string_literal: true

module Grsx
  # Raised when the preprocessor detects invalid RSX syntax.
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

  # GRSX Preprocessor — delegates to Parser + Codegen pipeline.
  #
  # Parses RSX source (Ruby + <Tag> extensions) into an AST,
  # then generates equivalent Phlex DSL Ruby code.
  #
  # Usage:
  #   Grsx::Preprocessor.new.preprocess(source) # => Phlex Ruby code string
  #
  class Preprocessor
    # Backward-compatible constant aliases.
    # Canonical definitions live in Grsx::Elements.
    HTML_VOID_ELEMENTS   = Elements::VOID
    SVG_ELEMENTS         = Elements::SVG
    KNOWN_HTML_ELEMENTS  = Elements::KNOWN
    JSX_ATTR_CORRECTIONS = Elements::JSX_ATTR_CORRECTIONS

    attr_reader :resolver

    def initialize(resolver: nil)
      @resolver = resolver || Grsx.configuration.element_resolver
    end

    def preprocess(source, source_map: false)
      ast = Grsx::Parser.new(source, resolver: @resolver).parse
      Grsx::Codegen.new(ast, resolver: @resolver, source_map: source_map).generate
    end
  end
end
