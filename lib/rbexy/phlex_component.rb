require "phlex"
require "phlex-rails"

module Rbexy
  # Base class for JSX-backed Phlex components.
  #
  # Define your props in initialize, write your template in a co-located .rbx
  # file. Rbexy compiles the .rbx into a real view_template method — no eval
  # at render time.
  #
  #   # app/components/card_component.rb
  #   class CardComponent < Rbexy::PhlexComponent
  #     def initialize(title:)
  #       @title = title
  #     end
  #   end
  #
  #   # app/components/card_component.rbx
  #   <div class="card">
  #     <h2>{@title}</h2>
  #     {content}
  #   </div>
  #
  class PhlexComponent < Phlex::HTML
    include Phlex::Rails::Helpers

    # --- Slot / child content ---

    # Called inside a .rbx template as {content} to yield children written
    # by the caller:
    #
    #   <CardComponent title="Hi">
    #     <p>I am a child</p>
    #   </CardComponent>
    #
    # This maps directly to the JSX children slot pattern. Phlex 2.x passes
    # children as a block to view_template, so {content} in a .rbx template
    # compiles to a bare `yield`.
    def content
      yield
    end

    # --- Expression output ---

    # Handles all { ruby_expr } interpolations in compiled templates:
    # - Phlex component   → render() (shares buffer, no string round-trip)
    # - Phlex safe value  → raw()
    # - nil / ""          → no-op
    # - anything else     → plain().to_s (auto-escaped by CGI.escapeHTML)
    def __rbx_expr_out(value)
      case value
      when Phlex::SGML
        render(value)
      when Phlex::SGML::SafeObject
        raw(value)
      when nil, ""
        nil
      else
        plain(value.to_s)
      end
    end

    # --- Template loading ---

    class << self
      # Template cache: { path => { mtime: Time, code: String } }
      TEMPLATE_CACHE = {}
      private_constant :TEMPLATE_CACHE

      def inherited(subclass)
        super
        subclass.load_rbx_template
      end

      # Locate, compile, and define view_template from the co-located .rbx file.
      # Called once when the class is first loaded. In development mode the
      # template is recompiled whenever the file changes.
      def load_rbx_template
        path = rbx_template_path
        return unless path && File.exist?(path)

        compiled = compile_template(path)
        define_view_template(compiled)
        @_rbx_template_path = path
      end

      # Recompile and redefine view_template if the .rbx file has changed.
      # Call this from a Rack middleware or before_action in development.
      def reload_rbx_template_if_changed
        path = @_rbx_template_path
        return unless path
        mtime = File.mtime(path)
        cached = TEMPLATE_CACHE[path]
        return if cached && cached[:mtime] == mtime

        compiled = compile_template(path)
        define_view_template(compiled)
      end

      private

      # Derive the .rbx path from the Ruby source file of the subclass.
      # Falls back to looking in the caller's directory.
      def rbx_template_path
        source = source_location
        return nil unless source

        base = File.basename(source, ".rb")
        dir  = File.dirname(source)
        File.join(dir, "#{base}.rbx")
      end

      def source_location
        # Walk the ancestor chain to find the Ruby file where this class is defined.
        # instance_method(:initialize).source_location is the most reliable hook.
        loc = instance_method(:initialize).source_location rescue nil
        loc&.first
      end

      def compile_template(path)
        mtime = File.mtime(path)
        cached = TEMPLATE_CACHE[path]
        return cached[:code] if cached && cached[:mtime] == mtime

        source = File.read(path)
        template = Rbexy::Template.new(source, path)
        code = Rbexy.phlex_compile(template)

        TEMPLATE_CACHE[path] = { mtime: mtime, code: code }
        code
      end

      def define_view_template(compiled_code)
        # Define view_template as a real method body — no eval at render time.
        # frozen_string_literal is intentionally not applied here because the
        # compiled code contains dynamic string literals from the template.
        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def view_template
            #{compiled_code}
          end
        RUBY
      end
    end
  end
end
