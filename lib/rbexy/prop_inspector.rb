module Rbexy
  # Walks a compiled Phlex code string (or a Rbexy AST) and collects every
  # @ivar name referenced in the template.
  #
  # This powers the `props` DSL — it lets us tell the user which props are
  # actually used in a template without requiring manual declaration.
  #
  # Usage:
  #   code = Rbexy.phlex_compile(template)
  #   names = Rbexy::PropInspector.scan_code(code)
  #   # => [:title, :body, :user]
  #
  # Or directly from a parse tree:
  #   root = Rbexy::Parser.new(tokens).parse
  #   names = Rbexy::PropInspector.scan_tree(root)
  #
  class PropInspector
    # Regex that matches @ivar names in the already-compiled Phlex code string.
    # Matches patterns like @title, @user_name, @items123
    IVAR_PATTERN = /@([a-z_][a-zA-Z0-9_]*)/.freeze

    # Scan compiled Phlex code (a Ruby string) for @ivar references
    # and return them as an array of symbols.
    def self.scan_code(code)
      code.scan(IVAR_PATTERN).map { |m| m.first.to_sym }.uniq.sort
    end

    # Recursively walk a Rbexy AST root node and collect @ivar identifiers
    # from all expression nodes. Returns a sorted, unique array of symbols.
    def self.scan_tree(root)
      names = []
      walk(root, names)
      names.sort.uniq
    end

    private_class_method def self.walk(node, names)
      case node
      when Nodes::Root
        node.children.each { |c| walk(c, names) }
      when Nodes::HTMLElement, Nodes::ComponentElement
        node.members.each { |m| walk(m, names) }
        (node.children || []).each { |c| walk(c, names) }
      when Nodes::ExpressionGroup
        node.members.each { |m| walk(m, names) }
      when Nodes::Expression
        node.content.scan(IVAR_PATTERN).each { |m| names << m.first.to_sym }
      when Nodes::HTMLAttr, Nodes::ComponentProp
        walk(node.value, names) if node.respond_to?(:value)
      end
    end
  end
end
