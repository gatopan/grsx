module Grsx
  module Nodes
    class ExpressionGroup < AbstractNode
      attr_accessor :members
      attr_reader :outer_template, :inner_template

      def initialize(members, outer_template: nil, inner_template: nil)
        @members = members
        @outer_template = outer_template
        @inner_template = inner_template
      end
    end
  end
end

