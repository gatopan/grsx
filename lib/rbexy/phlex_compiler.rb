module Rbexy
  # Converts a Rbexy AST into a Ruby string of Phlex DSL method calls.
  #
  # The emitted code is suitable for evaluation inside a Rbexy::PhlexComponent
  # (or Rbexy::PhlexRuntime for standalone use).  All output goes through
  # Phlex's structural buffer — no ActionView @output_buffer.
  #
  # Key mappings from JSX → Phlex DSL:
  #
  #   <div class="foo">text</div>   → div(class: "foo") { plain("text") }
  #   <br />                        → br
  #   <Button label={x} />         → render(ButtonComponent.new(label: x))
  #   <Card>{content}</Card>       → render(Card.new) { yield_content }
  #   {"Hello"}                    → plain("Hello")  (CGI.escapeHTML called)
  #   {render MyComp.new}          → render(MyComp.new)  (structural, shared buffer)
  #   {content}                    → yield_content  (slot pattern in components)
  #
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
      when Nodes::HTMLElement      then compile_html(node)
      when Nodes::ComponentElement then compile_component(node)
      when Nodes::Fragment         then compile_fragment(node)
      when Nodes::ExpressionGroup  then compile_expression_group(node)
      when Nodes::Text             then compile_text(node)
      when Nodes::Newline          then ""
      when Nodes::Declaration      then compile_declaration(node)
      else
        raise "PhlexCompiler: unknown AST node #{node.class}"
      end
    end

    # <></> → children rendered inline, no wrapper element.
    # The JSX fragment pattern eliminates the need for meaningless <div> wrappers.
    def compile_fragment(node)
      compile_nodes(node.children)
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
          key = normalize_html_attr_key(m.name)
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

    # <Button label={@title} disabled />  — key prop is silently dropped
    # → render ButtonComponent.new(label: @title, disabled: "")
    def compile_component(node)
      kwargs_parts = []
      node.members.each do |m|
        case m
        when Nodes::ComponentProp
          # Strip the React `key` prop — it has no server-side meaning and
          # would otherwise cause an ArgumentError on the Ruby component.
          next if m.name == "key"

          key = normalize_component_prop_key(m.name)
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

    # { ruby_expr } in text position:
    #
    #   {content}        → yield_content  (children slot)
    #   {"Hello"}        → __rbx_expr_out("Hello")  → plain() with auto-escape
    #   {render Foo.new} → __rbx_expr_out(render Foo.new)
    def compile_expression_group(node)
      # Special case: bare `content` identifier → forward children via Phlex yield
      if content_call?(node)
        return "yield"
      end

      expr = compile_expression_group_value(node)
      "__rbx_expr_out(#{expr})"
    end

    # Returns true when the expression group is a bare `content` identifier.
    # This is the JSX children-slot pattern: {content}
    def content_call?(node)
      node.members.length == 1 &&
        node.members.first.is_a?(Nodes::Expression) &&
        node.members.first.content.strip == "content"
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

    # Normalize HTML attribute names to Ruby keyword argument keys.
    #
    # One rule: kebab-case → snake_case (the only transformation needed
    # to make HTML attribute names legal Ruby keyword arguments).
    #
    #   class            → class       (Phlex accepts `class:` just fine)
    #   data-controller  → data_controller  (Phlex re-emits as data-controller)
    #   aria-label       → aria_label      (Phlex re-emits as aria-label)
    #   for              → for         (no htmlFor nonsense)
    #   id, src, href    → unchanged
    #
    # We do NOT do camelCase → snake_case. That's a React-ism: React uses
    # camelCase because JSX is JavaScript where `class` / `for` are reserved.
    # In rbx we're in Ruby; write HTML attributes as HTML writes them.
    def normalize_html_attr_key(name)
      name.tr("-", "_")
    end

    # Normalize component prop names to Ruby keyword argument keys.
    #
    # Component props map directly to Ruby kwargs, so we accept both
    # HTML-style kebab-case and Ruby snake_case:
    #   card-title  → card_title  (kebab, HTML-like)
    #   card_title  → card_title  (snake, Ruby-like, unchanged)
    #
    # camelCase props are also normalized via ActiveSupport::Inflector
    # since component props are Ruby identifiers, not HTML attributes:
    #   cardTitle   → card_title  (reasonable to accept in component context)
    def normalize_component_prop_key(name)
      # Kebab-to-underscore first, then underscore for camelCase
      ActiveSupport::Inflector.underscore(name.tr("-", "_"))
    end
  end
end
