# frozen_string_literal: true

require "active_support/inflector"

module Grsx
  # AST → Phlex Ruby source code generator.
  #
  # Walks the AST produced by Parser and emits equivalent Phlex DSL code.
  #
  # ── Line-aligned output ───────────────────────────────────────────
  #
  # The compiled output maintains 1:1 line alignment with the RSX source:
  # compiled line N = RSX source line N. This is achieved by padding with
  # blank lines before each node to match its source location.
  #
  # Combined with class_eval/instance_eval's (file, line) arguments, this
  # gives Ruby exact file:line mapping for error backtraces — no source map
  # comments needed.
  #
  # Usage:
  #   ast = Parser.new(source, resolver: resolver).parse
  #   code = Codegen.new(ast, resolver: resolver).generate
  #
  class Codegen
    attr_reader :resolver

    def initialize(nodes, resolver: nil, svg_depth: 0)
      @nodes = nodes
      @resolver = resolver || Grsx.resolver
      @svg_depth = svg_depth
      @output = +""
      @current_line = 1
    end

    def generate
      emit_nodes(@nodes)
      @output
    end

    private

    # ── Line alignment ───────────────────────────────────────────────
    # Before emitting code for a node, pad with blank lines so that the
    # node's compiled line matches its RSX source line. This is the core
    # mechanism for error line fidelity.

    def pad_to(node)
      return unless node.respond_to?(:location) && node.location

      target = node.location.line
      while @current_line < target
        @output << "\n"
        @current_line += 1
      end
    end

    def emit(code)
      @output << code
      @current_line += code.count("\n")
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
      emit(node.source)
    end

    def emit_text(node)
      pad_to(node)
      result = node.content
      result = " " + result if node.leading_space
      result = result + " " if node.trailing_space
      emit("plain(#{result.inspect});")
    end

    def emit_expr(node)
      pad_to(node)
      if node.source == "content"
        emit("yield;")
      else
        emit("__rsx_expr_out(#{node.source});")
      end
    end

    def emit_tag(node)
      pad_to(node)
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
          emit("#{phlex_name};")
        else
          emit("#{phlex_name}(#{attrs_str});")
        end
      else
        block_args = entering_svg ? " |s|" : ""
        if attrs_str.empty?
          emit("#{phlex_name} {#{block_args} ")
        else
          emit("#{phlex_name}(#{attrs_str}) {#{block_args} ")
        end
        @svg_depth += 1 if entering_svg
        emit_children_with_spacing(node.children)
        @svg_depth -= 1 if entering_svg
        emit(" };")
      end
    end

    def emit_component_tag(node)
      component_expr = resolve_component_name(node.name)
      attrs_str = format_component_attrs(node.attrs)
      kwargs = attrs_str.empty? ? "" : "(#{attrs_str})"

      if node.self_closing
        emit("render(#{component_expr}.new#{kwargs});")
      else
        emit("render(#{component_expr}.new#{kwargs}) { ")
        emit_children_with_spacing(node.children)
        emit(" };")
      end
    end

    def emit_fragment(node)
      pad_to(node)
      emit_children_with_spacing(node.children)
    end

    def emit_block_expr(node)
      pad_to(node)
      emit("#{node.preamble}; ")
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
            emit(node.source)
          else
            prev_node = i > 0 ? children[i - 1] : nil
            produces_output = prev_node.is_a?(AST::Tag) || prev_node.is_a?(AST::Expr) || prev_node.is_a?(AST::BlockExpr)
            if node.source.include?(" ") && produces_output
              emit("plain(\" \")\n")
            else
              emit(node.source)
            end
          end
        elsif node.is_a?(AST::Text)
          prev_node = i > 0 ? children[i - 1] : nil
          produces_output = prev_node.is_a?(AST::Tag) || prev_node.is_a?(AST::Expr) || prev_node.is_a?(AST::BlockExpr)
          result = node.content
          result = " " + result if node.leading_space && produces_output
          result = result + " " if node.trailing_space
          pad_to(node)
          emit("plain(#{result.inspect})\n")
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
