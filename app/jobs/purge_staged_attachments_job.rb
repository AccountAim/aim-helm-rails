module AimHelmRails
  class PurgeStagedAttachmentsJob < ApplicationJob
    queue_as :agent

    def perform
      Attachment.staged.where(created_at: ...Attachment::STAGING_TTL.ago).find_each do
        purge(it)
      end
    end

    private

    def purge(attachment)
      attachment.with_lock { attachment.destroy! if attachment.session_id.nil? }
    rescue ActiveRecord::RecordNotFound
      # Another cleanup worker already removed this staged upload.
      nil
    end
  end
end
