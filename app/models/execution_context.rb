module AimHelmRails
  # actor: who is acting now; owner: whose chat it is, the same person unless the chat is shared.
  ExecutionContext = Data.define(:actor, :tenant, :owner) do
    def initialize(actor:, tenant:, owner: actor) = super
  end
end
