# A host store for specs: the port over a hash, scoped like a real one would be.
class MemoryStore
  Feature = AimHelmRails::Features::Workspace
  STORES = Hash.new { |all, scope| all[scope] = {} }

  def self.reset = STORES.clear

  attr_reader :root

  def initialize(kind:, tenant:, actor: nil, root: "")
    @documents = STORES[[kind.to_s, tenant, actor]]
    @root = root
    @readonly = false
  end

  def readonly = dup.tap { it.instance_variable_set(:@readonly, true) }
  def read(path) = @documents["#{root}#{path}"]

  def write(path, content)
    raise Feature::ReadOnly, "read-only" if @readonly

    @documents["#{root}#{Feature.path!(path)}"] = content
    nil
  end

  def delete(path) = @documents.delete("#{root}#{path}")

  def list(prefix = nil, text: nil)
    paths = @documents.keys.select { it.start_with?(root) }.map { it.delete_prefix(root) }.sort
    paths = paths.select { it.start_with?(prefix) } if prefix
    text ? paths.select { it.include?(text) || read(it).include?(text) } : paths
  end

  def entries(prefix = nil, text: nil)
    list(prefix, text:).map { [it, read(it).bytesize, read(it).count("\n"), Time.now] }
  end

  def atomic_writes? = true

  def snapshot(path)
    content = read(path)
    Feature::Snapshot.for(content) if content
  end

  def compare_and_write(path, content, expected_revision:)
    raise Feature::ConflictError, path unless snapshot(path)&.revision == expected_revision

    write(path, content)
    snapshot(path)
  end
end
