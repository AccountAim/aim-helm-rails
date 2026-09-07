module AimHelmRails
  module Identities
    extend ActiveSupport::Concern

    included do
      scope :within, -> { where(tenant_gid: it.to_gid.to_s) }
      scope :by, -> { where(actor_gid: it.to_gid.to_s) }

      validates :tenant_gid, presence: true
    end

    def actor = GlobalID::Locator.locate(actor_gid)
    def tenant = GlobalID::Locator.locate(tenant_gid)

    def actor=(record)
      self.actor_gid = record&.to_gid&.to_s
    end

    def tenant=(record)
      self.tenant_gid = record.to_gid.to_s
    end
  end
end
