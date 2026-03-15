# frozen_string_literal: true

module Grsx
  class Template
    attr_reader :source, :identifier

    def initialize(source, identifier = "")
      @source = source
      @identifier = identifier
    end
  end
end
