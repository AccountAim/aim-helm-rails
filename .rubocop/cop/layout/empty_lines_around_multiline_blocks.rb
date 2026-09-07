# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # .rubocop.yml runs this against lib/**/*.rb to separate multiline control flow.
      class EmptyLinesAroundMultilineBlocks < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Add an empty line %<side>s this multiline block."
        BLOCK_TYPES = %i[begin block case case_match for if kwbegin numblock until while].freeze

        def on_new_investigation
          processed_source.ast&.each_node(*BLOCK_TYPES) { check(it) }
        end

        private

        def check(node)
          return unless node.multiline? && node.parent&.begin_type?

          check_side(node.left_sibling, node, :before)
          check_side(node, node.right_sibling, :after)
        end

        def check_side(left, right, side)
          return unless left && right
          return unless right.first_line == left.last_line + 1
          return if comments_between?(left, right)

          spacing = range_between(left.source_range.end_pos, right.source_range.begin_pos)
          add_offense(spacing, message: format(MSG, side:)) do
            it.replace(spacing, "\n\n#{" " * right.loc.column}")
          end
        end

        def comments_between?(left, right)
          processed_source.comments.any? do
            it.location.line.between?(left.last_line + 1, right.first_line - 1)
          end
        end
      end
    end
  end
end
