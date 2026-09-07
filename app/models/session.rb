module AimHelmRails
  class Session < ApplicationRecord
    include Identities

    attribute :id, default: -> { SecureRandom.uuid_v7 }

    validates :actor_gid, presence: true
    validate :parent_tenant_must_match

    belongs_to :parent_session, class_name: "AimHelmRails::Session", optional: true
    has_many :child_sessions,
             class_name: "AimHelmRails::Session",
             foreign_key: :parent_session_id,
             inverse_of: :parent_session,
             dependent: :destroy
    has_many :entries,
             class_name: "AimHelmRails::SessionEntry",
             inverse_of: :session,
             dependent: :destroy
    has_many :attachments, class_name: "AimHelmRails::Attachment", dependent: :destroy

    enum :status,
         %w[queued running awaiting_approval awaiting_subagent completed failed stopped]
           .index_by(&:itself),
         validate: true

    class << self
      def aim_helm_create!(context:, id: nil, parent: nil, name: nil)
        create!({ id:, actor: context.actor, tenant: context.tenant,
                  parent_session: parent, name: }.compact)
      end
    end

    # `render chat` is the whole chat, on any page.
    def to_partial_path = "aim_helm_rails/chats/chat"

    # Subagents run in their own sessions; the chat is the tree they hang from.
    def root = parent_session_id ? parent_session.root : self

    def aim_helm_context
      ExecutionContext.new(actor: GlobalID::Locator.locate(execution_actor_gid || actor_gid),
                           tenant:)
    end

    def title = name.presence || history.title
    def message_count = history.message_count
    def history_runs = history.runs
    def context_pin = aside_pin&.payload&.dig("metadata", "resource")
    def aside_pin = history.aside_pin
    def usage = AimHelm.session(id).usage

    def setup
      run = entries.where(kind: "run_record").order(:id).last
      run ? run.payload.slice("model", "reasoning").symbolize_keys : {}
    end

    private

    def history = History.new(entries, child_sessions:)

    def parent_tenant_must_match
      return unless parent_session && parent_session.tenant_gid != tenant_gid

      errors.add(:parent_session, "must belong to the same tenant")
    end
  end
end
