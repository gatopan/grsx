# frozen_string_literal: true

module Grsx
  class Configuration
    attr_writer :element_resolver

    def element_resolver
      @element_resolver ||= ComponentResolver.new
    end
  end
end
