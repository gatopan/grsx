module Grsx
  class Configuration
    attr_accessor :template_paths
    attr_accessor :debug

    def template_paths
      @template_paths ||= []
    end

    def element_resolver
      @element_resolver ||= ComponentResolver.new
    end
  end
end
