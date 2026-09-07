module AimHelmRails
  module Chats
    class MessagesController < ApplicationController
      def create
        Session.transaction do
          @chat = sessions.find_by(id: params[:chat_id]) || open_chat
          authorize_chat!
          @attached = claim_attachments
          Runtime.run(chat, prompt, actor: current_actor, tenant: current_tenant) if message?
        end

        bind_response
        head :no_content
      end

      private

      # A chat's first post creates it. One opened on something starts with the agent looking at
      # it, so its first post may carry nothing typed.
      attr_reader :chat, :attached

      def open_chat
        raise ActiveRecord::RecordNotFound if Session.exists?(id: params[:chat_id])

        AimHelmRails.host.open_chat(
          actor: current_actor, tenant: current_tenant, id: params[:chat_id],
          helmsman: helmsman_name, context: params[:context]
        )
      end

      def helmsman_name
        AimHelmRails.host.interactive_helmsman(message_params[:helmsman]).helmsman_name
      end

      def authorize_chat!
        AimHelmRails.host.authorize!(chat, actor: current_actor, tenant: current_tenant,
                                           action: :update)
      end

      def claim_attachments
        Attachment.claim!(Array(message_params[:attachments]), session: chat,
                                                               actor: current_actor,
                                                               tenant: current_tenant)
      end

      def sessions
        AimHelmRails.host.sessions(actor: current_actor, tenant: current_tenant)
                    .within(current_tenant)
      end

      def message? = message_params[:content].present? || attached.any?

      # Typed text travels tagged: the transcript shows only <user-message> content, so
      # machine-authored blocks (signals, attachments) stay out of the bubbles by default.
      def prompt
        typed = "<user-message>#{message_params[:content]}</user-message>"
        Attachments.encode(typed, attached)
      end

      def message_params
        @message_params ||= params.expect(message: [:content, :helmsman, { attachments: [] }])
                                  .to_h.symbolize_keys
      end

      def bind_response
        host = AimHelmRails.host
        response.headers.merge!({
          "X-Agent-Session-Id" => chat.id,
          "X-Agent-Session-Path" => host.session_path(chat),
          "X-Agent-Context-Pane" => host.context_pane(chat).to_json,
          "X-Agent-Run-Id" => AimHelm.session(chat.id).pending_run_id,
        }.compact)
      end
    end
  end
end
