module Rbexy
  module Rails
    class Engine < ::Rails::Engine
      # In development, hot-reload .rbx templates for PhlexComponent subclasses
      # on every request via a lightweight Rack middleware.
      initializer "rbexy.phlex_reloader" do |app|
        dev_mode = if app.config.respond_to?(:enable_reloading)
          app.config.enable_reloading
        else
          !app.config.cache_classes
        end

        if dev_mode
          require "rbexy/rails/phlex_reloader"
          app.middleware.use Rbexy::Rails::PhlexReloader
        end

        Rbexy.configure do |config|
          config.template_paths << ::Rails.root.join("app", "components")
        end
      end
    end
  end
end
