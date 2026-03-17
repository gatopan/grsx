# frozen_string_literal: true

require "prism"

module Grsx
  # Prism-extended RSX compiler using AST-guided body extraction.
  #
  # Strategy B: Use Prism's error-recovering AST to locate method bodies,
  # then compile only those bodies with parse_ruby_context.
  #
  # Flow:
  #   1. Prism.parse(source) → AST with DefNodes (even with RSX errors)
  #   2. Visitor finds all DefNode boundaries (exact byte offsets)
  #   3. For each def body containing `<tag>`: compile with parse_ruby_context
  #   4. Reassemble: Ruby structure (class/def/end) + compiled bodies
  #
  # This gives us:
  #   - Prism handles Ruby structure (class, def, end, props, blocks)
  #   - parse_ruby_context handles RSX (bare if/else/end + <tag> interception)
  #   - No heuristics, no regex method detection, no text-continuation bugs
  #
  class ExtendedParser
    def initialize(source, resolver: nil)
      @source = source
      @resolver = resolver || Grsx.resolver
    end

    # Compile .rsx source into pure Ruby (Phlex DSL).
    def compile
      result = Prism.parse(@source)
      defs = find_def_nodes(result.value)

      # Fallback: files without class/def (fragments, views)
      # Compile the entire source as a method body
      if defs.empty?
        return @source unless @source.match?(/<[A-Za-z]/)
        return compile_body(@source)
      end

      output = +""
      pos = 0

      defs.each do |defn|
        body_start = defn[:body_start]
        body_end = defn[:body_end]
        body_src = @source[body_start...body_end]

        # Skip pure-Ruby methods (no HTML/component tags)
        next unless body_src&.match?(/<[A-Za-z]/)

        # Copy everything before this method body as-is
        output << @source[pos...body_start]

        # Compile the method body with parse_ruby_context
        compiled = compile_body(body_src)
        output << compiled

        pos = body_end
      end

      # Copy remaining source after the last compiled body
      rest = @source[pos..]
      output << rest if rest
      output
    end

    private

    # Walk Prism AST to find all DefNode boundaries.
    # Returns array of { name:, body_start:, body_end: } hashes.
    def find_def_nodes(ast)
      defs = []
      collector = Class.new(Prism::Visitor) {
        define_method(:visit_def_node) do |node|
          if node.body && node.end_keyword_loc
            defs << {
              name: node.name,
              body_start: node.body.location.start_offset,
              body_end: node.end_keyword_loc.start_offset
            }
          end
          super(node)
        end
      }
      ast.accept(collector.new)
      defs
    end

    # Compile a method body using parse_ruby_context.
    # The body is just the method innards — no def/end wrapper.
    # parse_ruby_context handles:
    #   - bare if/else/end → Ruby passthrough
    #   - <tag>...</tag> → RSX → Phlex DSL
    #   - {expr} inside tag children → expression interpolation
    def compile_body(body_source)
      ast = Parser.new(body_source, resolver: @resolver).parse
      Codegen.new(ast, resolver: @resolver).generate
    end
  end
end
