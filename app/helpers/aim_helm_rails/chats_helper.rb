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

    # The host's list, or the one key a chat was opened on.
    def aim_helm_rails_chat_choices(chat)
      offered = AimHelmRails.host.chat_options
      key = chat.helmsman
      return offered unless key

      [offered.find { it[:key] == key } || { key:, label: key }]
    end
  end
end
