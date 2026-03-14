module Rbexy
  # Converts a Rbexy AST into a Ruby string of Phlex DSL method calls that can
  # be evaluated inside a Rbexy::PhlexRuntime (a Phlex::HTML subclass).
  #
  # This is an alternative to the default ActionView codegen path which emits
  # @output_buffer.safe_concat(...) strings.
  #
  # Usage:
  #   tree = Rbexy::Parser.new(tokens).parse
  #   code = Rbexy::PhlexCompiler.new(tree).compile
  #   Rbexy::PhlexRuntime.new(view_context: ctx, assigns: assigns).call { eval(code) }
  class PhlexCompiler
    HTML_VOID_ELEMENTS = %w(area base br col embed hr img input link meta source track wbr).to_set

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def compile
      compile_nodes(root.children)
    end

    private

    def compile_nodes(nodes)
      nodes.map { |n| compile_node(n) }.join("\n")
    end

    def compile_node(node)
      case node
      when Nodes::HTMLElement    then compile_html(node)
      when Nodes::ComponentElement then compile_component(node)
      when Nodes::ExpressionGroup  then compile_expression_group(node)
      when Nodes::Text             then compile_text(node)
      when Nodes::Newline          then ""
      when Nodes::Declaration      then compile_declaration(node)
      else
        raise "PhlexCompiler: unknown AST node #{node.class}"
      end
    end

    # <div class="foo"> ... </div>
    # → div(class: "foo") do ... end
    def compile_html(node)
      tag_name = node.name
      attrs = compile_html_attrs(node.members)

      if HTML_VOID_ELEMENTS.include?(tag_name)
        # void: <br /> → br
        attrs.empty? ? tag_name : "#{tag_name}(#{attrs})"
      elsif node.children.empty?
        # no children: <span class="x" /> → span(class: "x") {}
        attrs.empty? ? "#{tag_name} {}" : "#{tag_name}(#{attrs}) {}"
      else
        inner = compile_nodes(node.children)
        if attrs.empty?
          "#{tag_name} do\n#{inner}\nend"
        else
          "#{tag_name}(#{attrs}) do\n#{inner}\nend"
        end
      end
    end

    # Build keyword argument string from HTMLAttr and ExpressionGroup (splat) members
    def compile_html_attrs(members)
      parts = []
      members.each do |m|
        case m
        when Nodes::HTMLAttr
          key = m.name.tr("-", "_")
          val = compile_attr_value(m.value)
          parts << "#{key}: #{val}"
        when Nodes::ExpressionGroup
          # {**spread_hash} → spread into tag kwargs
          parts << "**#{compile_expression_group_value(m)}"
        when Nodes::Newline
          # ignore
        end
      end
      parts.join(", ")
    end

    def compile_attr_value(node)
      case node
      when Nodes::Text             then node.content.inspect
      when Nodes::ExpressionGroup  then compile_expression_group_value(node)
      else node.class.name
      end
    end

    # <Button label={@title} disabled />
    # → render ButtonComponent.new(label: @title, disabled: "")
    def compile_component(node)
      kwargs_parts = []
      node.members.each do |m|
        case m
        when Nodes::ComponentProp
          key = ActiveSupport::Inflector.underscore(m.name)
          val = compile_attr_value(m.value)
          kwargs_parts << "#{key}: #{val}"
        when Nodes::ExpressionGroup
          kwargs_parts << "**#{compile_expression_group_value(m)}"
        when Nodes::Newline then next
        end
      end

      kwargs = kwargs_parts.join(", ")
      component_expr = kwargs.empty? ? "::#{node.name}.new" : "::#{node.name}.new(#{kwargs})"

      if node.children.any?
        inner = compile_nodes(node.children)
        "render(#{component_expr}) {\n#{inner}\n}"
      else
        "render(#{component_expr})"
      end
    end

    # { ruby_expr } in text position → plain(ruby_expr)
    # Phlex's plain() auto-escapes via CGI.escapeHTML
    def compile_expression_group(node)
      expr = compile_expression_group_value(node)
      "__rbx_expr_out(#{expr})"
    end

    # Returns the raw ruby expression string (no output call wrap)
    def compile_expression_group_value(node)
      node.members.map { |m| compile_expression_value(m) }.join
    end

    def compile_expression_value(node)
      case node
      when Nodes::Expression         then node.content
      when Nodes::HTMLElement        then compile_html(node)
      when Nodes::ComponentElement   then compile_component(node)
      when Nodes::ExpressionGroup    then "(#{compile_expression_group_value(node)})"
      else node.class.name
      end
    end

    # Static text: "Hello" → plain("Hello")
    def compile_text(node)
      "plain(#{node.content.inspect})"
    end

    # <!DOCTYPE html> → raw(safe("<!DOCTYPE html>"))
    def compile_declaration(node)
      "raw(safe(#{node.content.inspect}))"
    end
  end
end
