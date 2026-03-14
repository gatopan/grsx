module Grsx
  module Nodes
    class AbstractNode
      # Compact adjacent Raw/Newline nodes into a single Raw node.
      # Used by the parser when building the AST.
      private

      def compact(nodes)
        compacted = []
        curr_raw = nil

        nodes.each do |node|
          if node.is_a?(Newline) && curr_raw
            curr_raw.merge(Raw.new("\n"))
          elsif node.is_a?(Raw)
            if !curr_raw
              curr_raw ||= Raw.new("")
              compacted << curr_raw
            end
            curr_raw.merge(node)
          else
            curr_raw = nil
            compacted << node
          end
        end

        compacted
      end
    end
  end
end
