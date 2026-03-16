# frozen_string_literal: true

require "active_support/inflector"

module Grsx
  # AST → Phlex Ruby source code generator.
  #
  # Walks the AST produced by Parser and emits equivalent Phlex DSL code.
  #
  # Options:
  #   source_map: true — emit `# line N` pragmas so Ruby stack traces
  #                      point back to original RSX line numbers.
  #
  # Usage:
  #   ast = Parser.new(source, resolver: resolver).parse
  #   code = Codegen.new(ast, resolver: resolver).generate
  #
  #   # With source maps (for production use):
  #   code = Codegen.new(ast, source_map: true).generate
  #
  class Codegen
    SVG_ELEMENTS = Elements::SVG

    attr_reader :resolver

    def initialize(nodes, resolver: nil, svg_depth: 0, source_map: false)
      @nodes = nodes
      @resolver = resolver || Grsx.configuration.element_resolver
      @svg_depth = svg_depth
      @source_map = source_map
      @output = +""
      @last_mapped_line = nil
    end

    def generate
      emit_nodes(@nodes)
      @output
    end

    private

    # Emit a `# line N` pragma if source mapping is enabled and the node
    # has a location that hasn't been mapped yet. Ruby uses this to set
    # the line number in stack traces, making errors point to the original
    # RSX source instead of the compiled Phlex code.
    def source_map(node)
      return unless @source_map
      return unless node.respond_to?(:location) && node.location

      line = node.location.line
      return if line == @last_mapped_line

      @last_mapped_line = line
      @output << "# line #{line}\n"
    end

    def emit_nodes(nodes)
      nodes.each { |node| emit_node(node) }
    end

    def emit_node(node)
      case node
      when AST::RubyCode   then emit_ruby(node)
      when AST::Text       then emit_text(node)
      when AST::Expr       then emit_expr(node)
      when AST::Tag        then emit_tag(node)
      when AST::Fragment   then emit_fragment(node)
      when AST::BlockExpr  then emit_block_expr(node)
      else
        raise "Unknown AST node: #{node.class}"
      end
    end

    # ── Node Emitters ─────────────────────────────────────────────

    def emit_ruby(node)
      @output << node.source
    end

    def emit_text(node)
      source_map(node)
      result = node.content
      result = " " + result if node.leading_space
      result = result + " " if node.trailing_space
      @output << "plain(#{result.inspect})\n"
    end

    def emit_expr(node)
      source_map(node)
      if node.source == "content"
        @output << "yield\n"
      else
        @output << "__rsx_expr_out(#{node.source})\n"
      end
    end

    def emit_tag(node)
      source_map(node)
      case node.kind
      when :html, :svg then emit_html_tag(node)
      when :component  then emit_component_tag(node)
      end
    end

    def emit_html_tag(node)
      prefix = node.kind == :svg ? "s." : ""
      phlex_name = "#{prefix}#{node.name}"
      attrs_str = format_html_attrs(node.attrs)
      entering_svg = node.name == "svg" && !node.self_closing

      if node.self_closing
        if attrs_str.empty?
          @output << "#{phlex_name}\n"
        else
          @output << "#{phlex_name}(#{attrs_str})\n"
        end
      else
        block_args = entering_svg ? " |s|" : ""
        if attrs_str.empty?
          @output << "#{phlex_name} do#{block_args}\n"
        else
          @output << "#{phlex_name}(#{attrs_str}) do#{block_args}\n"
        end
        @svg_depth += 1 if entering_svg
        emit_children_with_spacing(node.children)
        @svg_depth -= 1 if entering_svg
        @output << "end\n"
      end
    end

    def emit_component_tag(node)
      component_expr = resolve_component_name(node.name)
      attrs_str = format_component_attrs(node.attrs)
      kwargs = attrs_str.empty? ? "" : "(#{attrs_str})"

      if node.self_closing
        @output << "render(#{component_expr}.new#{kwargs})"
      else
        @output << "render(#{component_expr}.new#{kwargs}) do\n"
        emit_children_with_spacing(node.children)
        @output << "end\n"
      end
    end

    def emit_fragment(node)
      source_map(node)
      emit_children_with_spacing(node.children)
    end

    def emit_block_expr(node)
      source_map(node)
      @output << "#{node.preamble}\n"
      emit_nodes(node.children)
    end

    # ── Children Spacing ──────────────────────────────────────────
    # Handle whitespace-only RubyCode nodes between elements.
    # If a whitespace-only node sits between two output-producing nodes
    # (tags, exprs, text), emit plain(" ") to preserve the space.

    def emit_children_with_spacing(children)
      children.each_with_index do |node, i|
        if node.is_a?(AST::RubyCode) && node.source.strip.empty?
          # Whitespace-only Ruby — check context.
          # If it contains newlines, it's indentation → pass through verbatim.
          # If same-line spaces between output-producing nodes → plain(" ").
          if node.source.include?("\n")
            @output << node.source
          else
            prev_node = i > 0 ? children[i - 1] : nil
            produces_output = prev_node.is_a?(AST::Tag) || prev_node.is_a?(AST::Expr) || prev_node.is_a?(AST::BlockExpr)
            if node.source.include?(" ") && produces_output
              @output << "plain(\" \")\n"
            else
              @output << node.source
            end
          end
        elsif node.is_a?(AST::Text)
          prev_node = i > 0 ? children[i - 1] : nil
          produces_output = prev_node.is_a?(AST::Tag) || prev_node.is_a?(AST::Expr) || prev_node.is_a?(AST::BlockExpr)
          result = node.content
          result = " " + result if node.leading_space && produces_output
          result = result + " " if node.trailing_space
          source_map(node)
          @output << "plain(#{result.inspect})\n"
        else
          emit_node(node)
        end
      end
    end

    # ── Attribute Formatting ──────────────────────────────────────

    def format_html_attrs(attrs)
      parts = attrs.map do |attr|
        if attr.splat
          "**#{attr.value.source}"
        elsif attr.value.nil?
          "#{normalize_html_attr_key(attr.name)}: true"
        elsif attr.value.static?
          "#{normalize_html_attr_key(attr.name)}: #{attr.value.source.inspect}"
        else
          "#{normalize_html_attr_key(attr.name)}: #{attr.value.source}"
        end
      end
      parts.join(", ")
    end

    def format_component_attrs(attrs)
      parts = attrs.map do |attr|
        if attr.splat
          "**#{attr.value.source}"
        elsif attr.value.nil?
          "#{normalize_component_prop_key(attr.name)}: true"
        elsif attr.value.static?
          "#{normalize_component_prop_key(attr.name)}: #{attr.value.source.inspect}"
        else
          "#{normalize_component_prop_key(attr.name)}: #{attr.value.source}"
        end
      end
      parts.join(", ")
    end

    # ── Name Resolution ───────────────────────────────────────────

    def resolve_component_name(tag_name)
      base = tag_name.gsub(".", "::")
      "__resolve_rsx_const(\"#{base}\")"
    end

    def normalize_html_attr_key(name)
      name.tr("-", "_")
    end

    def normalize_component_prop_key(name)
      ActiveSupport::Inflector.underscore(name.tr("-", "_"))
    end
  end
end
