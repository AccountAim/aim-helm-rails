module AimHelmRails
  module Chats
    class MessagesController < ApplicationController
      # The first post to a chat's id creates it. A chat opened on something may post nothing
      # typed, so the agent can start on it.
      def create
        Session.transaction do
          host.authorize!(chat, actor: current_actor, tenant: current_tenant, action: :update)
          Runtime.run(chat, prompt, actor: current_actor, tenant: current_tenant) if message?
        end

        bind_headers
        head :no_content
      end

      private

      def host = AimHelmRails.host
      def chat = @chat ||= sessions.find_by(id: params[:chat_id]) || open_chat

      def sessions
        host.sessions(actor: current_actor, tenant: current_tenant).within(current_tenant)
      end

      def open_chat
        raise ActiveRecord::RecordNotFound if Session.exists?(id: params[:chat_id])

        host.open_chat(actor: current_actor, tenant: current_tenant, id: params[:chat_id],
                       options: ChatOptions.new(message[:key]), context: params[:context])
      end

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

      def bind_headers
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
