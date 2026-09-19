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

    # [{ key: "analyst:gpt-5.6-terra/low", label: "Analyst, quick" }, …]
    def aim_helm_rails_chat_options(chat) = ChatOptions.for(chat)
  end
end
