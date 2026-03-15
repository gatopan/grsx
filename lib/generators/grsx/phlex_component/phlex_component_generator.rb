# frozen_string_literal: true

require "rails/generators"

module Grsx
  module Generators
    class PhlexComponentGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :slots, type: :array, default: [],
        desc: "Named content slots to declare (e.g. --slots header footer)"

      desc "Creates a Grsx::PhlexComponent with a co-located .rsx template"

      def create_component_file
        template "component.rb.tt", component_rb_path
      end

      def create_template_file
        template "component.rsx.tt", component_rsx_path
      end

      private

      def component_rb_path
        File.join("app", "components", class_path, "#{file_name}_component.rb")
      end

      def component_rsx_path
        File.join("app", "components", class_path, "#{file_name}_component.rsx")
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
