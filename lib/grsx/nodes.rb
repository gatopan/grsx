module Grsx
  module Nodes
    # --- Base classes ---

    class AbstractNode
    end

    class AbstractElement < AbstractNode
      attr_accessor :name, :members, :children

      def initialize(name, members, children)
        @name = name
        @members = members || []
        @children = children
      end
    end

    class AbstractAttr < AbstractNode
      attr_accessor :name, :value

      def initialize(name, value)
        @name = name
        @value = value
      end
    end

    # --- Elements ---

    class HTMLElement < AbstractElement
    end

    class ComponentElement < AbstractElement
    end

    # --- Attributes ---

    class HTMLAttr < AbstractAttr
    end

    class ComponentProp < AbstractAttr
    end

    # --- Value nodes ---

    class Root < AbstractNode
      attr_accessor :children

      def initialize(children)
        @children = children
      end
    end

    # A Fragment wraps children without emitting a DOM element.
    # Corresponds to the JSX <></> syntax.
    class Fragment < AbstractNode
      attr_accessor :children

      def initialize(children)
        @children = children
      end
    end

    class Text < AbstractNode
      attr_accessor :content

      def initialize(content)
        @content = content
      end
    end

    class Declaration < AbstractNode
      attr_accessor :content

      def initialize(content)
        @content = content
      end
    end

    class Expression < AbstractNode
      attr_accessor :content

      def initialize(content)
        @content = content
      end
    end

    class ExpressionGroup < AbstractNode
      attr_accessor :members

      def initialize(members)
        @members = members
      end
    end

    class Raw < AbstractNode
      attr_reader :content

      def initialize(content)
        @content = content
      end
    end

    class Newline < AbstractNode
    end
  end
end
