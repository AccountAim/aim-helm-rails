module AimHelmRails
  # Attachment gids ride in the durable prompt, listed after the person's own words. Encoding and
  # decoding live together so the transcript can show what was attached without re-reading the tags.
  module Attachments
    BLOCK = %r{\n*<attachments>\n.*?\n</attachments>\n*}m
    GID = /gid="([^"]+)"/
    THUMBNAIL_SIZES = { "small" => 320, "large" => 1200 }.freeze

    module_function

    def encode(content, attachments)
      return content if attachments.empty?

      tags = attachments.map { %(  <attachment gid="#{it.to_gid_param}"/>) }
      [content.presence, "<attachments>", *tags, "</attachments>"].compact.join("\n")
    end

    def decode(text)
      listed = text[BLOCK]
      return { content: text, gids: [] } unless listed

      { content: text.sub(BLOCK, "").strip, gids: listed.scan(GID).flatten }
    end

    def resolve(gids, session:)
      session.root.attachments.where(id: Attachment.ids_for(gids)).map { reference(it) }
    end

    def reference(attachment)
      {
        gid: attachment.to_gid_param,
        name: attachment.filename.to_s,
        url: Engine.routes.url_helpers.attachment_path(attachment),
        thumbnail_url: thumbnail_path(attachment),
      }
    end

    # Representations are generated when first requested, so a transcript can point at one before
    # anything has drawn it.
    def thumbnail_path(attachment)
      return unless attachment.representable?

      Engine.routes.url_helpers.thumbnail_attachment_path(attachment)
    end
  end
end
