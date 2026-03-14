require "rails/generators"

module Rbexy
  module Generators
    class PhlexComponentGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :slots, type: :array, default: [],
        desc: "Named content slots to declare (e.g. --slots header footer)"

      desc "Creates a Rbexy::PhlexComponent with a co-located .rbx template"

      def create_component_file
        template "component.rb.tt", component_rb_path
      end

      def create_template_file
        template "component.rbx.tt", component_rbx_path
      end

      private

      def component_rb_path
        File.join("app", "components", class_path, "#{file_name}_component.rb")
      end

      def component_rbx_path
        File.join("app", "components", class_path, "#{file_name}_component.rbx")
      end

      def slot_names
        options[:slots]
      end

      def component_class_name
        "#{class_name}Component"
      end
    end
  end
end
