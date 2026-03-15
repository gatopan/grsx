# frozen_string_literal: true

require "set"

module Grsx
  class ComponentResolver
    # Standard HTML5 elements only. SVG elements are not listed — they pass
    # through as HTML tags via the fallback path (Phlex renders them as raw
    # tag names, which is correct for SVG).
    KNOWN_HTML_ELEMENTS = %w(
      a abbr address area article aside audio b base bdi bdo blockquote body br button canvas
      caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed
      fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html i
      iframe img input ins kbd label legend li link main map mark menu meta meter nav noscript
      object ol optgroup option output p param picture pre progress q rp rt ruby s samp script
      search section select slot small source span strong style sub summary sup table tbody td
      template textarea tfoot th thead time title tr track u ul var video wbr
    ).to_set.freeze

    def self.try_constantize
      yield
    rescue NameError => e
      raise e unless e.message =~ /wrong constant name/ || e.message =~ /uninitialized constant/
      nil
    end

    attr_reader :component_namespaces

    def initialize
      self.component_namespaces = {}
    end

    def component_namespaces=(hash)
      @component_namespaces = hash.transform_keys(&:to_s)
    end

    def component?(name, template)
      return false if KNOWN_HTML_ELEMENTS.include?(name)
      return true if component_class(name, template)
      false
    end

    def component_class(name, template)
      possible_names = matching_namespaces(template).map { |ns| "#{ns}.#{name}" } << name
      possible_names.each do |n|
        result = find(n)
        return result if result
      end
      nil
    end

    private

    def find(name)
      self.class.try_constantize { ActiveSupport::Inflector.constantize("#{name.gsub(".", "::")}Component") }
    end

    def matching_namespaces(template)
      component_namespaces.select { |path, ns| template.identifier.start_with?(path) }.values.flatten.uniq
    end
  end
end
