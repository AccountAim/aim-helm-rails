module AimHelmRails
  class AttachmentsController < ApplicationController
    MAX_FILES = 6
    MAX_TOTAL_BYTES = 25.megabytes

    before_action :authorize_upload!, only: :create

    def create
      files = attachment_params
      refused = limit_error(files)
      return render_error(refused) if refused

      attachments = Attachment.transaction { files.map { store(it) } }
      render json: { attachments: attachments.map { reference(it) } },
             status: :created
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages.to_sentence)
    end

    def show
      attachment.file.blob.open do
        send_data it.read, type: attachment.content_type, filename: attachment.title,
                           disposition: :inline
      end
    end

    def thumbnail
      size = Attachments::THUMBNAIL_SIZES.fetch(params.fetch(:size, "small")) do
        raise ActionController::BadRequest, "unknown thumbnail size"
      end
      representation = attachment.thumbnail(size).processed
      send_data representation.download, type: representation.content_type, disposition: :inline
    end

    private

    def authorize_upload!
      AimHelmRails.host.authorize_upload!(actor: current_actor, tenant: current_tenant)
    end

    def attachment_params = Array(params.permit(files: [])[:files])

    def attachment
      @attachment ||= Attachment.within(current_tenant).find(params[:id]).tap do
        AimHelmRails.host.authorize!(it, actor: current_actor, tenant: current_tenant,
                                         action: :read)
      end
    end

    def limit_error(files)
      return "Attach between 1 and #{MAX_FILES} files." unless files.size.in?(1..MAX_FILES)
      return unless files.sum(&:size) > MAX_TOTAL_BYTES

      "Attach #{MAX_TOTAL_BYTES / 1.megabyte} MB of files or less."
    end

    def store(file)
      attachment = Attachment.new(actor: current_actor, tenant: current_tenant)
      attachment.file.attach(file)
      attachment.save!
      attachment
    end

    def reference(attachment)
      Attachments.reference(attachment).merge(
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
      )
    end

    def render_error(message) = render json: { error: message }, status: :unprocessable_content
  end
end
