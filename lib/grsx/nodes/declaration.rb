module Grsx
  module Nodes
    class Declaration < AbstractNode
      attr_accessor :content

      def initialize(content)
        @content = content
      end
    end
  end
end
