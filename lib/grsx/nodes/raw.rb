module Grsx
  module Nodes
    class Raw < AbstractNode
      attr_reader :content

      def initialize(content)
        @content = content
      end

      def merge(other_raw)
        content << other_raw.content
      end
    end
  end
end
