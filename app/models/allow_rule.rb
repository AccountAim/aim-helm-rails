module AimHelmRails
  class AllowRule < ApplicationRecord
    include Identities

    validates :actor_gid, :tool_name, presence: true
  end
end
