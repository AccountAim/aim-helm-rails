module AimHelmRails
  class WorkspaceDocument < ApplicationRecord
    include Identities

    validates :kind, :key, :path, presence: true
    validates :kind, :key, length: { maximum: 128 }
    validates :path, length: { maximum: 512 }
  end
end
