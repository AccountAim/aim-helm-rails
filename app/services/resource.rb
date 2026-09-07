module AimHelmRails
  module Resource
    module_function

    # { gid:, placement:, title: } -> a lazy host-rendered frame.
    def presentation(reference, key:)
      reference = reference.symbolize_keys
      gid = reference.fetch(:gid)
      frame = reference[:placement] == "aside" ? "context" : "resource_#{Digest::SHA256.hexdigest("#{key}:#{gid}")}"

      reference.merge(id: frame, src: AimHelmRails.host.resource_path(gid, frame:))
    end
  end
end
