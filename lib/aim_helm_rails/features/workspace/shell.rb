module AimHelmRails
  module Features
    class Workspace
      # Runs a script in a sandbox whose home, /scratch, holds the whole scratch space, with the
      # listed documents from other stores mounted at /<mount>/<path>. Only files under /scratch
      # are saved back, new or changed; a change anywhere else is discarded and reported.
      # Nothing is ever deleted from a store.
      class Shell
        # The one writable mount; "scratch/clips/a.txt" saves as clips/a.txt in the scratch store.
        SCRATCH_ROOT = "scratch".freeze
        OUTPUT_LIMIT = 64.kilobytes # what the script's stdout is cut to for the agent
        # Bashkit bounds every command's output at this, rg included, even into a pipe or file;
        # far above OUTPUT_LIMIT so `rg -o big | sort -u` sees every match.
        SANDBOX_OUTPUT = 8.megabytes
        TIMEOUT_SECONDS = 10
        COMMAND_NOT_FOUND = 127
        OUTPUT_SIZE = ActiveSupport::NumberHelper.number_to_human_size(OUTPUT_LIMIT)
        CUT = "\n… [output cut at #{OUTPUT_SIZE}; redirect into scratch/ or filter further]".freeze

        GUIDE = <<~TEXT.freeze
          A sandboxed bash with the files named in paths mounted at the same path. Only writes under
          scratch/ are kept; /tmp is cleared after each call. Text commands only, rg, sed, awk, jq,
          sort and the like; no interpreters, no network. Each call is a fresh shell. Output over
          #{OUTPUT_SIZE} is cut.

            ls -R scratch; wc -l scratch/clips/x/published.sql  # what is here, how big
            rg -n -i -C 2 'double count' knowledge_base/app/*.md  # the lines around each hit
            rg -o "THEN '[^']+'" scratch/clips/x/published.sql | sort -u  # every distinct label, once
            rg -n JOIN knowledge_base/app/platform.md > scratch/hits.txt  # keep a result
        TEXT

        UNLISTED = "the /scratch listing was cut; only the files in written were saved".freeze

        Report = Data.define(:result, :written, :discarded, :commands, :listing_cut) do
          def to_h
            { exit_code: result.exit_code, stdout:, stderr: result.stderr.presence,
              error: result.error, written: written.presence,
              discarded: discarded.presence, available_commands: commands,
              warning: (UNLISTED if listing_cut) }.compact
          end

          def stdout
            out = result.stdout
            return out unless result.stdout_truncated || out.bytesize > OUTPUT_LIMIT

            "#{out.byteslice(0, OUTPUT_LIMIT).scrub("")}#{CUT}"
          end
        end

        # stores: { "scratch" => adapter, "knowledge_base" => adapter, … }
        def self.call(stores, script, paths:) = new(stores).call(script, paths)

        def initialize(stores)
          @stores = stores
        end

        def call(script, paths)
          paths = paths.map { validate(it) }
          seeded = paths.to_h { [it, read(it)] }.compact
          bash = sandbox(seeded, paths)
          result = bash.execute(script)
          report(bash, seeded, result)
        ensure
          bash&.close
        end

        private

        attr_reader :stores

        def report(bash, seeded, result)
          created, listing_cut = created_in_scratch(bash)

          Report.new(
            result:,                                       # exit code, stdout, stderr, cut flag
            commands: available_commands(bash, result),    # runnable commands, after a missing one
            written: write_to_store(bash, seeded, created), # scratch paths saved this run
            discarded: readonly_edits(bash, seeded),       # read-only paths the script changed
            listing_cut:,                                  # /scratch held more files than listed
          )
        end

        # A `paths` entry: a known mount, then a document path under it.
        def validate(path)
          mount, rest = path.split("/", 2)
          raise InvalidPath, "unknown mount in #{path.inspect}" unless stores.key?(mount)

          "#{mount}/#{Workspace.path!(rest)}"
        end

        # "knowledge_base/app/x.md" → that store's "app/x.md"
        def read(path)
          mount, rest = path.split("/", 2)
          stores.fetch(mount).read(rest)
        end

        # A fresh sandbox holding the seeded files, with a directory per mount and requested path.
        def sandbox(seeded, paths)
          bash = AimHelmBashkit::Bash.new(
            cwd: "/", timeout_seconds: TIMEOUT_SECONDS,
            max_output_bytes: SANDBOX_OUTPUT,
            files: seeded.transform_keys { "/#{it}" }
          )
          stores.each_key { bash.mkdir("/#{it}", recursive: true) }
          paths.each { bash.mkdir(File.dirname("/#{it}"), recursive: true) }
          bash
        end

        # Saves seeded scratch files that changed and any file the script created under /scratch.
        def write_to_store(bash, seeded, created)
          candidates = seeded.keys.select { it.start_with?("#{SCRATCH_ROOT}/") } | created

          candidates.filter_map do
            content = read_file(bash, it)
            next if content.nil? || content == seeded[it]

            stores.fetch(SCRATCH_ROOT).write(it.delete_prefix("#{SCRATCH_ROOT}/"), content)
            it
          end
        end

        # Files under /scratch after the script ran, and whether the listing was cut. A cut listing
        # keeps its whole lines; a partial last path is dropped.
        def created_in_scratch(bash)
          listing = bash.execute("find /#{SCRATCH_ROOT} -type f")
          return [[], true] if listing.error || !listing.success?

          paths = listing.stdout.lines(chomp: true)
          paths.pop if listing.stdout_truncated && !listing.stdout.end_with?("\n")
          [paths.map { it.delete_prefix("/") }, listing.stdout_truncated]
        end

        # Edits to files outside /scratch never reach a store; they are named so the script knows.
        def readonly_edits(bash, seeded)
          seeded.keys.reject { it.start_with?("#{SCRATCH_ROOT}/") }
                .reject { read_file(bash, it) == seeded[it] }
        end

        # What the sandbox can run, for a script that asked for something else.
        def available_commands(bash, result)
          return unless result.exit_code == COMMAND_NOT_FOUND

          bash.execute("compgen -c | sort -u").stdout.split.join(" ")
        end

        # A file the script removed reads as nil.
        def read_file(bash, path)
          bash.read_file("/#{path}")
        rescue AimHelmBashkit::Error => e
          raise unless e.code == AimHelmBashkit::Native::IO_ERROR

          nil
        end
      end
    end
  end
end
