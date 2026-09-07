# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # .rubocop.yml runs this against lib/**/*.rb to separate multiline constant assignments.
      class EmptyLinesAroundMultilineConstants < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Add an empty line around this multiline constant definition."

        def on_new_investigation
          processed_source.ast&.each_node(:begin) do
            it.children.each_cons(2) { |left, right| check(left, right) }
          end
        end

        private

        def check(left, right)
          return unless multiline_constant?(left) || multiline_constant?(right)
          return unless right.first_line == left.last_line + 1
          return if comments_between?(left, right)

          spacing = range_between(left.source_range.end_pos, right.source_range.begin_pos)
          add_offense(spacing) do
            it.replace(spacing, "\n\n#{" " * right.loc.column}")
          end
        end

        def multiline_constant?(node) = node.casgn_type? && node.multiline?

        def comments_between?(left, right)
          processed_source.comments.any? do
            it.location.line.between?(left.last_line + 1, right.first_line - 1)
          end
        end
      end
    end
  end
end
