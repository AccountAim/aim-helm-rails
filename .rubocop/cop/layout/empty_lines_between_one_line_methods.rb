module RuboCop
  module Cop
    module Layout
      class EmptyLinesBetweenOneLineMethods < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Remove empty lines between one-line method definitions.".freeze

        def on_class(node) = check(node.body)
        def on_module(node) = check(node.body)

        private

        def check(body)
          statements(body).each_cons(2) { check_pair(*it) }
        end

        def check_pair(left, right)
          return unless one_line_method?(left) && one_line_method?(right)
          return unless right.first_line > left.last_line + 1
          return if comments_between?(left, right)

          spacing = range_between(left.source_range.end_pos, right.source_range.begin_pos)
          add_offense(spacing) { it.replace(spacing, "\n#{" " * right.loc.column}") }
        end

        def statements(body) = body&.begin_type? ? body.children : [body].compact
        def one_line_method?(node) = node.def_type? && node.single_line?

        def comments_between?(left, right)
          processed_source.comments.any? do
            it.location.line.between?(left.last_line + 1, right.first_line - 1)
          end
        end
      end
    end
  end
end
