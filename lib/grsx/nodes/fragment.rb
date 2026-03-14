module Grsx
  module Nodes
    # A Fragment node renders its children without a wrapping element.
    # It corresponds to the JSX <></> syntax.
    #
    # In JSX:
    #   <>
    #     <h1>Title</h1>
    #     <p>Body</p>
    #   </>
    #
    # Compiled Phlex DSL: just the children inline, no wrapper.
    class Fragment < AbstractNode
      attr_accessor :children

      def initialize(children)
        @children = children
      end

      # ActionView codegen: compile children directly, no wrapper tag
      def precompile
        children.map(&:precompile).flatten
      end

      def compile
        children.map(&:compile).join
      end
    end
  end
end
