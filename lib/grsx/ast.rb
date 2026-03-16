# frozen_string_literal: true

module Grsx
  # AST node types for the GRSX preprocessor pipeline.
  #
  # The RSX grammar has one syntactic extension over Ruby: <Tag> patterns.
  # Everything else is Ruby passthrough. This yields a small, flat AST:
  #
  #   Program = [Node]
  #   Node    = RubyCode | Tag | Fragment | Text | Expr | BlockExpr
  #   Tag     = { name, attrs: [Attr], children: [Node], self_closing, kind }
  #   Attr    = { name, value: AttrValue?, splat }
  #
  module AST
    # Base for all nodes — carries source location for error reporting.
    Location = Struct.new(:line, :col, keyword_init: true)

    # ── Pretty-Printing ──────────────────────────────────────────────
    # Mix this into all node types for readable tree output.
    # Usage: puts ast  or  pp Grsx::Parser.new(source).parse

    module PrettyPrint
      def to_s(indent = 0)
        pad = "  " * indent
        case self
        when RubyCode
          src = source.strip
          src = src[0..40] + "…" if src.length > 40
          "#{pad}RubyCode(#{src.inspect})"
        when Text
          flags = []
          flags << "leading_space" if leading_space
          flags << "trailing_space" if trailing_space
          extra = flags.any? ? " [#{flags.join(", ")}]" : ""
          "#{pad}Text(#{content.inspect}#{extra})"
        when Expr
          "#{pad}Expr(#{source})"
        when Tag
          line = "#{pad}Tag(:#{kind}, #{name.inspect}"
          line += ", self_closing" if self_closing
          unless attrs.empty?
            attr_strs = attrs.map { |a| a.to_s(0) }
            line += ", attrs=[#{attr_strs.join(", ")}]"
          end
          if children.empty?
            line + ")"
          else
            lines = [line + ")"]
            children.each { |c| lines << c.to_s(indent + 1) }
            lines.join("\n")
          end
        when Fragment
          lines = ["#{pad}Fragment()"]
          children.each { |c| lines << c.to_s(indent + 1) }
          lines.join("\n")
        when BlockExpr
          lines = ["#{pad}BlockExpr(#{preamble.inspect})"]
          children.each { |c| lines << c.to_s(indent + 1) }
          lines.join("\n")
        when Attr
          if splat
            "Attr(splat: #{value&.source})"
          elsif value.nil?
            "Attr(#{name}, boolean)"
          else
            "Attr(#{name}=#{value.source.inspect})"
          end
        when AttrValue
          "AttrValue(#{source.inspect}, #{kind})"
        else
          "#{pad}#{self.class.name.split("::").last}(...)"
        end
      end

      def inspect
        to_s
      end
    end

    # ── Leaf Nodes ──────────────────────────────────────────────────

    # Verbatim Ruby code — passed through unchanged.
    RubyCode = Struct.new(:source, :location, keyword_init: true) do
      include PrettyPrint
    end

    # Prose text content — wrapped in `plain(...)`.
    Text = Struct.new(:content, :leading_space, :trailing_space, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(content:, location:, leading_space: false, trailing_space: false)
        super(content: content, leading_space: leading_space, trailing_space: trailing_space, location: location)
      end
    end

    # Expression interpolation: `{expr}` → `__rsx_expr_out(expr)`.
    Expr = Struct.new(:source, :location, keyword_init: true) do
      include PrettyPrint
    end

    # ── Compound Nodes ──────────────────────────────────────────────

    # HTML element, SVG element, or custom component.
    # kind: :html, :component, :svg
    Tag = Struct.new(:name, :attrs, :children, :self_closing, :kind, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(name:, location:, attrs: [], children: [], self_closing: false, kind: :html)
        super(name: name, attrs: attrs, children: children, self_closing: self_closing, kind: kind, location: location)
      end
    end

    # Fragment: `<>...</>` — renders children without a wrapper element.
    Fragment = Struct.new(:children, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(children: [], location:)
        super(children: children, location: location)
      end
    end

    # Block expression: `{link_to path do <i/>  end}` — Ruby call with RSX body.
    BlockExpr = Struct.new(:preamble, :block_args, :children, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(preamble:, location:, block_args: nil, children: [])
        super(preamble: preamble, block_args: block_args, children: children, location: location)
      end
    end

    # ── Attribute Nodes ─────────────────────────────────────────────

    # Tag attribute: `name="value"`, `name={expr}`, `name` (boolean), `{**expr}` (splat).
    Attr = Struct.new(:name, :value, :splat, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(name: nil, value: nil, splat: false, location: nil)
        super(name: name, value: value, splat: splat, location: location)
      end
    end

    # Attribute value — either a static string or a dynamic Ruby expression.
    AttrValue = Struct.new(:source, :kind, :location, keyword_init: true) do
      include PrettyPrint

      def initialize(source:, kind: :static, location: nil)
        super(source: source, kind: kind, location: location)
      end

      def static? = kind == :static
      def dynamic? = kind == :dynamic
    end
  end
end
