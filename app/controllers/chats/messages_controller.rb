module AimHelmRails
  module Chats
    class MessagesController < ApplicationController
      def create
        Session.transaction do
          host.authorize!(chat, actor: current_actor, tenant: current_tenant, action: :update)
          Runtime.run(chat, prompt, actor: current_actor, tenant: current_tenant) if message?
        end

        announce_chat
        head :no_content
      end

      private

      def host = AimHelmRails.host

      # The first post to a chat's id creates it here.
      def chat = @chat ||= sessions.find_by(id: params[:chat_id]) || open_chat

      def sessions
        host.sessions(actor: current_actor, tenant: current_tenant).within(current_tenant)
      end

      def open_chat
        raise ActiveRecord::RecordNotFound if Session.exists?(id: params[:chat_id])

        host.open_chat(actor: current_actor, tenant: current_tenant, id: params[:chat_id],
                       key: ChatKey.new(message[:key]), context: params[:context])
      end

      # Claims on first read, inside the create transaction.
      def attached
        @attached ||= Attachment.claim!(Array(message[:attachments]),
                                        session: chat, actor: current_actor, tenant: current_tenant)
      end

      def message = @message ||= params.expect(message: [:content, :key, { attachments: [] }])
      def message? = message[:content].present? || attached.any?

      # Typed text travels tagged: the transcript shows only <user-message> content, so
      # machine-authored blocks (signals, attachments) stay out of the bubbles.
      def prompt
        Attachments.encode("<user-message>#{message[:content]}</user-message>", attached)
      end

      def announce_chat
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
