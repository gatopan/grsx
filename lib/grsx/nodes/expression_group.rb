module Grsx
  module Nodes
    class ExpressionGroup < AbstractNode
      attr_accessor :members

      def initialize(members, **_ignored)
        @members = members
      end
    end
  end
end
