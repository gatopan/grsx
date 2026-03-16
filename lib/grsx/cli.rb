# frozen_string_literal: true

require "grsx"
require "grsx/lint"

module Grsx
  # Command-line interface for GRSX tools.
  #
  #   grsx lint [paths...]             # lint specific files
  #   grsx lint --project PATH         # lint all .rsx in a project
  #   grsx lint --format json          # machine-readable output
  #
  module CLI
    class << self
      def run(argv = ARGV)
        command = argv.shift
        case command
        when "lint"
          run_lint(argv)
        when "compile"
          run_compile(argv)
        when "--help", "-h", nil
          print_help
        else
          $stderr.puts "Unknown command: #{command}"
          print_help
          exit 1
        end
      end

      private

      def run_lint(argv)
        format = :text
        project = nil
        files = []

        while (arg = argv.shift)
          case arg
          when "--format"
            format = argv.shift&.to_sym || :text
          when "--project"
            project = argv.shift
          when "--help", "-h"
            print_lint_help
            return
          else
            files << arg
          end
        end

        if project
          lint_project(project, format)
        elsif files.any?
          lint_files(files, format)
        else
          # Default: lint current directory
          lint_project(".", format)
        end
      end

      def lint_project(dir, format)
        dir = File.expand_path(dir)
        results = Grsx::Lint.check_directory(dir)

        if format == :json
          print_json(results)
        else
          print_text(results)
        end

        exit results.values.any? { |ds| ds.any? { |d| d.severity == :error } } ? 1 : 0
      end

      def lint_files(files, format)
        results = {}
        files.each do |file|
          source = File.read(file)
          diagnostics = Grsx::Lint.check(source, filename: file)
          results[file] = diagnostics if diagnostics.any?
        end

        if format == :json
          print_json(results)
        else
          print_text(results)
        end

        exit results.values.any? { |ds| ds.any? { |d| d.severity == :error } } ? 1 : 0
      end

      def print_text(results)
        if results.empty?
          puts "✓ No issues found"
          return
        end

        error_count = 0
        warning_count = 0

        results.each do |file, diagnostics|
          diagnostics.each do |d|
            puts d.to_s
            if d.severity == :error
              error_count += 1
            else
              warning_count += 1
            end
          end
        end

        puts
        parts = []
        parts << "#{error_count} error#{'s' unless error_count == 1}" if error_count > 0
        parts << "#{warning_count} warning#{'s' unless warning_count == 1}" if warning_count > 0
        puts "#{results.size} file#{'s' unless results.size == 1} with issues: #{parts.join(', ')}"
      end

      def print_json(results)
        require "json"
        output = results.map do |file, diagnostics|
          {
            file: file,
            diagnostics: diagnostics.map do |d|
              { line: d.line, column: d.column, severity: d.severity.to_s, message: d.message }
            end
          }
        end
        puts JSON.pretty_generate(output)
      end

      def run_compile(argv)
        file = argv.shift
        unless file
          $stderr.puts "Usage: grsx compile <file>"
          exit 1
        end

        source = File.read(file)
        if file.include?(".html.rsx") || file.include?("views/")
          puts Grsx.compile(source)
        else
          puts Grsx::ExtendedParser.new(source).compile
        end
      end

      def print_help
        puts <<~HELP
          Usage: grsx <command> [options]

          Commands:
            lint      Lint .rsx files for errors and warnings
            compile   Compile an .rsx file and print the output

          Run 'grsx <command> --help' for more information.
        HELP
      end

      def print_lint_help
        puts <<~HELP
          Usage: grsx lint [files...] [options]

          Options:
            --project PATH    Lint all .rsx files under PATH
            --format FORMAT   Output format: text (default) or json
            -h, --help        Show this help

          Examples:
            grsx lint app/components/shared/user_dropdown.rsx
            grsx lint --project /path/to/rails/app
            grsx lint app/ --format json
        HELP
      end
    end
  end
end
