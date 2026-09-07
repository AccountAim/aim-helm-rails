module AimHelmRails
  class Attachment < ApplicationRecord
    include Identities

    KINDS = {
      "application/pdf" => :pdf,
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => :spreadsheet,
      "image/gif" => :image,
      "image/jpeg" => :image,
      "image/png" => :image,
      "image/webp" => :image,
    }.freeze

    MAX_BYTES = 10.megabytes
    STAGING_TTL = 1.day

    belongs_to :session, class_name: "AimHelmRails::Session", optional: true
    has_one_attached :file

    scope :staged, -> { where(session_id: nil) }

    validates :actor_gid, presence: true
    validate :file_must_be_supported
    validate :session_tenant_must_match

    class << self
      def ids_for(gids)
        gids.map do
          gid = GlobalID.parse(it)

          unless gid && gid.model_name == name && gid.app == GlobalID.app
            raise ActiveRecord::RecordNotFound
          end

          gid.model_id
        end.uniq
      end

      def claim!(gids, session:, actor:, tenant:)
        raise ActiveRecord::RecordNotFound unless session.tenant == tenant

        transaction do
          staged.within(tenant).by(actor).where(created_at: STAGING_TTL.ago..)
                .lock.find(ids_for(gids)).each { it.update!(session:) }
        end
      end
    end

    delegate :byte_size, :content_type, :filename, :representable?, to: :file

    def title = filename.to_s
    def kind = KINDS.fetch(content_type)
    def as_agent_json(**) = { gid: to_gid.to_param, filename: title, content_type: }

    # Images use a variant and PDFs preview their first page for the transcript chip.
    def thumbnail(limit) = file.representation(resize_to_limit: [limit, limit])

    private

    def session_tenant_must_match
      return unless session && session.tenant_gid != tenant_gid

      errors.add(:session, "must belong to the same tenant")
    end

    def file_must_be_supported
      return errors.add(:file, "must be attached") unless file.attached?

      unless file.content_type.in?(KINDS)
        errors.add(:file, "must be an XLSX, PDF, GIF, JPEG, PNG, or WebP")
      end

      return unless file.byte_size > MAX_BYTES

      errors.add(:file, "must be #{MAX_BYTES / 1.megabyte} MB or smaller")
    end
  end
end
