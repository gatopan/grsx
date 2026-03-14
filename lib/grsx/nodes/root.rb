module Grsx
  module Nodes
    class Root < AbstractNode
      attr_accessor :children

      def initialize(children)
        @children = children
      end
    end
  end
end
