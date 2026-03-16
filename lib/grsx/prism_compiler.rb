# frozen_string_literal: true

require "prism"

module Grsx
  # Single-pass RSX compiler that extends Ruby's grammar via Prism's lexer.
  #
  # Walks Prism's token stream to natively recognise RSX tag openings
  # (`LESS + IDENTIFIER`) as a grammar extension. Ruby tokens pass through
  # verbatim; RSX segments are compiled to Phlex DSL using the existing
  # StringScanner-based tag parser.
  #
  # Usage:
  #   compiled = Grsx::PrismCompiler.new.compile(source)
  #
  class PrismCompiler
    def initialize(resolver: nil)
      @resolver = resolver || Grsx.configuration.element_resolver
    end

    # Compile .rsx source into pure Ruby (Phlex DSL).
    # Returns a string that can be eval'd.
    def compile(source)
      tokens = Prism.lex(source).value.map(&:first)
      output = +""
      i = 0
      last_offset = 0

      while i < tokens.length
        tok = tokens[i]
        next_tok = tokens[i + 1]

        if rsx_tag_open?(tok, next_tok)
          # Emit any Ruby source between the last position and this tag
          output << source[last_offset...tok.location.start_offset]

          # Compile the RSX segment starting at this offset
          segment_start = tok.location.start_offset
          ast_nodes, segment_end = parse_rsx_segment(source, segment_start)
          output << generate(ast_nodes)

          # Advance past the consumed tokens
          last_offset = segment_end
          i += 1 while i < tokens.length && tokens[i].location.start_offset < segment_end
        else
          i += 1
        end
      end

      # Emit remaining Ruby source after the last RSX segment
      output << source[last_offset..] if last_offset < source.length

      output
    end

    private

    # Detect RSX tag opening: `<` followed by a known HTML element or
    # uppercase component name. This is a deterministic grammar extension —
    # valid Ruby never produces `< identifier` in expression context where
    # identifier is an HTML element or starts uppercase.
    def rsx_tag_open?(tok, next_tok)
      return false unless tok.type == :LESS
      return false unless next_tok&.type == :IDENTIFIER || next_tok&.type == :CONSTANT

      name = next_tok.value
      html_element?(name) || component_name?(name)
    end

    def html_element?(name)
      Elements::KNOWN.include?(name)
    end

    def component_name?(name)
      name[0] == name[0].upcase
    end

    # Parse an RSX segment starting at `offset` in `source`.
    # Uses the existing StringScanner-based parser which handles
    # <tags>, attributes, and {expr} inside children natively.
    #
    # Returns [ast_nodes, end_offset] — the parsed AST and the byte offset
    # where the RSX segment ends (after the closing tag).
    def parse_rsx_segment(source, offset)
      segment = source[offset..]
      parser = Parser.new(segment, resolver: @resolver)

      # Parse a single tag (handles open tag, attributes, children, close tag)
      node = parser.send(:try_parse_tag_or_close)

      if node
        consumed = parser.instance_variable_get(:@scanner).pos
        [[node], offset + consumed]
      else
        # Not a valid tag — emit `<` as Ruby and advance 1 byte
        [[AST::RubyCode.new(source: "<", location: AST::Location.new(line: 0, col: 0))], offset + 1]
      end
    end

    def generate(ast_nodes)
      Codegen.new(ast_nodes, resolver: @resolver).generate
    end
  end
end
