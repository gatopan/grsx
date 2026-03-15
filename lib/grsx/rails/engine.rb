# frozen_string_literal: true

module Grsx
  module Rails
    class Engine < ::Rails::Engine
      # In development, hot-reload .rsx templates for PhlexComponent subclasses
      # on every request via a lightweight Rack middleware.
      initializer "grsx.phlex_reloader" do |app|
        dev_mode = if app.config.respond_to?(:enable_reloading)
          app.config.enable_reloading
        else
          !app.config.cache_classes
        end

        if dev_mode
          require "grsx/rails/phlex_reloader"
          app.middleware.use Grsx::Rails::PhlexReloader
        end

        Grsx.configure do |config|
          config.template_paths << ::Rails.root.join("app", "components")
        end
      end

      # Register .rsx as a first-class view template type so Rails
      # automatically discovers app/views/**/*.rsx files.
      initializer "grsx.template_handler" do
        ActiveSupport.on_load(:action_view) do
          require "grsx/template_handler"
          ActionView::Template.register_template_handler(:rsx, Grsx::TemplateHandler.new)
        end
      end
    end
  end
end
