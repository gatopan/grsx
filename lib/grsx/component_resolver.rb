# frozen_string_literal: true

require "set"

module Grsx
  class ComponentResolver
    # Standard HTML5 + SVG elements — delegates to Grsx::Elements.
    KNOWN_HTML_ELEMENTS = Elements::KNOWN

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
      class_name = name.gsub(".", "::")
      self.class.try_constantize { ActiveSupport::Inflector.constantize("#{class_name}Component") } ||
        self.class.try_constantize { ActiveSupport::Inflector.constantize(class_name) }
    end

    def matching_namespaces(template)
      component_namespaces.select { |path, ns| template.identifier.start_with?(path) }.values.flatten.uniq
    end
  end
end
