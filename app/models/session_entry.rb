module AimHelmRails
  class SessionEntry < ApplicationRecord
    belongs_to :session, inverse_of: :entries
  end
end
