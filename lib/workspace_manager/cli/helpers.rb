# frozen_string_literal: true

module WorkspaceManager
  module CLI
    module Helpers
      module_function

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def folder_entry(context, value)
        token = value.to_s.strip
        raise(Error, '--folder requires a target value') if blank?(token)

        path = resolve_folder(context, token)

        {
          path: path,
          name: File.basename(path)
        }
      end

      def resolve_folder(context, token)
        expanded = File.expand_path(token)
        return expanded if File.directory?(expanded)

        selected = Repo.select(context, token)
        File.expand_path(selected)
      end
    end
  end
end
