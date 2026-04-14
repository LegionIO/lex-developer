# frozen_string_literal: true

module Legion
  module Extensions
    module Developer
      module Helpers
        module ChangeParser
          extend self

          FILE_COMMENT_PATTERN = /\A#\s*file:\s*(.+)\z/
          CODE_BLOCK_PATTERN = /```\w*\n(.*?)```/m

          def parse(content:)
            return [] if content.nil? || content.strip.empty?

            blocks = content.scan(CODE_BLOCK_PATTERN).flatten
            blocks.filter_map { |block| extract_file_change(block) }
          end

          def file_paths_only(changes:)
            changes.map { |c| c[:path] }
          end

          private

          def extract_file_change(block)
            lines = block.lines
            first_line = lines.first&.strip

            match = first_line&.match(FILE_COMMENT_PATTERN)
            return nil unless match

            path = match[1].strip
            content = lines.drop(1).join

            { path: path, content: content }
          end
        end
      end
    end
  end
end
