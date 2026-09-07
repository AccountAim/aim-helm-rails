module RuboCop
  module Cop
    module Layout
      class HelperMethodAtTop < Base
        MSG = "Place helper_method declarations at the top of the controller.".freeze

        def on_class(node)
          statements = statements(node.body)
          first_non_helper = statements.index { !helper_method?(it) }
          return unless first_non_helper

          statements.drop(first_non_helper).select { helper_method?(it) }.each { add_offense(it) }
        end

        private

        def statements(body) = body&.begin_type? ? body.children : [body].compact

        def helper_method?(node)
          node.send_type? && node.receiver.nil? && node.method?(:helper_method)
        end
      end
    end
  end
end
