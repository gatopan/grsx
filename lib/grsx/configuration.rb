module Grsx
  class Configuration
    attr_writer :element_resolver

    # TODO: template_paths is set by the engine but not currently consumed
    # by PhlexComponent (which discovers .rbx files via caller_locations).
    # Kept for future use as a configurable lookup path.
    def template_paths
      @template_paths ||= []
    end

    def element_resolver
      @element_resolver ||= ComponentResolver.new
    end
  end
end
