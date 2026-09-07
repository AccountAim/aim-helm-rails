module AimHelmRails
  module ChatsHelper
    # Preloaded on the chat page alone: the island's whole graph, so it mounts with the first paint
    # while every other page stays free of it.
    ISLAND_MODULES = %w[
      vue marked dompurify
      aim_helm_rails/chat/app aim_helm_rails/chat/store aim_helm_rails/chat/usage
    ].freeze

    # CDN pins carry their own URL; engine files resolve through the asset pipeline.
    def aim_helm_rails_island_modules
      ISLAND_MODULES.map do
        Rails.application.importmap.packages[it]&.path || asset_path("#{it}.js")
      end
    end

    # [{ name: "analyst", label: "Analyst", description: "Answers…", setup: "terra/low" }, …]
    def aim_helm_rails_helmsmen(chat)
      AimHelmRails.host.interactive_helmsmen_for(chat).map do
        { name: it.helmsman_name, label: it.helmsman_name.humanize,
          description: it.helmsman_description, setup: aim_helm_rails_setup_label(chat, it) }
      end
    end

    def aim_helm_rails_setup_label(chat, helmsman)
      setup = chat.setup.presence || { model: helmsman.helmsman_model,
                                       reasoning: helmsman.helmsman_reasoning }
      "#{setup.fetch(:model).split("-").last}/#{setup[:reasoning]}"
    end
  end
end
