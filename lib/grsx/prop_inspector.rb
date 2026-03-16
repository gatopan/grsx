# frozen_string_literal: true

module Grsx
  # Scans compiled Phlex code for @ivar references.
  #
  # This powers the `props` DSL — it detects which props are used in
  # a template without requiring manual declaration.
  #
  # Usage:
  #   code = Grsx.compile(template_source)
  #   names = Grsx::PropInspector.scan_code(code)
  #   # => [:title, :body, :user]
  #
  class PropInspector
    # Regex that matches @ivar names in compiled Phlex code.
    IVAR_PATTERN = /@([a-z_][a-zA-Z0-9_]*)/.freeze

    # Scan compiled Phlex code (a Ruby string) for @ivar references
    # and return them as an array of symbols.
    def self.scan_code(code)
      code.scan(IVAR_PATTERN).map { |m| m.first.to_sym }.uniq.sort
    end
  end
end
