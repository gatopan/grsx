module Grsx
  module Nodes
    # A Fragment wraps children without emitting a DOM element.
    # Corresponds to the JSX <></> syntax.
    class Fragment < AbstractNode
      attr_accessor :children

      def initialize(children)
        @children = children
      end
    end
  end
end
