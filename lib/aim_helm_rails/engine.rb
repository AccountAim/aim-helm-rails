module AimHelmRails
  class Engine < ::Rails::Engine
    engine_name "aim_helm_rails"
    isolate_namespace AimHelmRails

    initializer "aim_helm_rails.autoloading", before: :setup_main_autoloader do
      root.glob("app/{controllers,jobs,models,services}").each do
        Rails.autoloaders.main.push_dir(it, namespace: AimHelmRails)
      end
    end

    initializer "aim_helm_rails.migrations" do
      it.config.paths["db/migrate"] << root.join("db/migrate")
    end

    initializer "aim_helm_rails.importmap", before: "importmap" do
      it.config.assets.paths << root.join("app/javascript")
      it.config.importmap.paths << root.join("config/importmap.rb")
      it.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "aim_helm_rails.runtime", after: "aim_helm.active_job" do
      it.config.to_prepare do
        AimHelmRails::HelmIntegration.apply
      end
    end

    initializer "aim_helm_rails.routes", after: :set_routes_reloader_hook do
      # Load routes before concurrent tool calls generate URLs.
      it.routes_reloader.execute_unless_loaded
    end
  end
end
