# frozen_string_literal: true

module Grsx
  # Static analysis engine for .rsx files.
  #
  # Catches compilation errors and common pitfalls before they
  # reach the browser.
  #
  #   diagnostics = Grsx::Lint.check(source, filename: "my_component.rsx")
  #   diagnostics.each { |d| puts d.to_s }
  #
  module Lint
    Diagnostic = Struct.new(:file, :line, :column, :severity, :message, :source_line) do
      def to_s
        loc = "#{file}:#{line}:#{column}"
        "#{loc}: #{severity}: #{message}" + (source_line ? "\n  #{line} | #{source_line.rstrip}" : "")
      end
    end

    class << self
      # Check a single .rsx source string.
      # Returns an Array of Diagnostic structs.
      #
      # Options:
      #   filename: — used in error messages (default: "<stdin>")
      #   mode:     — :component (ExtendedParser) or :view (Grsx.compile)
      #             Auto-detected from filename if not specified.
      def check(source, filename: "<stdin>", mode: nil)
        mode ||= detect_mode(filename)
        diagnostics = []

        # Phase 1: Heuristic warnings — only for common, high-confidence patterns
        diagnostics.concat(check_heuristics(source, filename, mode))

        # Phase 2: Compilation check — the main value
        diagnostics.concat(check_compilation(source, filename, mode))

        diagnostics
      end

      # Lint all .rsx files under a directory.
      # Returns { path => [Diagnostic, ...] }
      def check_directory(dir, component_dirs: ["app/components"], view_dirs: ["app/views"])
        results = {}

        Dir.glob(File.join(dir, "**/*.rsx")).sort.each do |path|
          relative = path.delete_prefix(dir).delete_prefix("/")
          mode = if component_dirs.any? { |d| relative.start_with?(d) }
                   :component
                 elsif view_dirs.any? { |d| relative.start_with?(d) }
                   :view
                 else
                   detect_mode(path)
                 end

          diagnostics = check(File.read(path), filename: relative, mode: mode)
          results[relative] = diagnostics if diagnostics.any?
        end

        results
      end

      private

      def detect_mode(filename)
        if filename.include?(".html.rsx") || filename.include?("views/")
          :view
        else
          :component
        end
      end

      # ── Phase 1: Heuristic warnings ──────────────────────────────
      #
      # Conservative checks for high-confidence mistakes. We avoid
      # trying to reimplement the parser's context tracking — that
      # would create false positives. Instead we flag only patterns
      # that are *never* correct in .rsx files.
      def check_heuristics(source, filename, _mode)
        diagnostics = []
        lines = source.lines

        lines.each_with_index do |line, idx|
          lineno = idx + 1
          stripped = line.strip

          # Skip empty lines and HTML comments
          next if stripped.empty? || stripped.start_with?("<!--")

          # ── Bare `# comment` on a line that's indented inside a tag ──
          #
          # In pure Ruby context (class body, method body before any tags),
          # `# comment` is a valid Ruby comment. But inside tag children,
          # it renders as visible text.
          #
          # We only flag this if the line is indented (suggesting it's inside
          # a tag) AND it's purely a comment (nothing else on the line).
          # Lines at column 0 are likely class/file-level comments.
          if stripped.match?(/\A#\s/) && line.match?(/\A\s{2,}#\s/)
            # Check if there's a preceding opening tag that hasn't been closed
            # by looking at previous lines for HTML tags
            context = lines[0...idx].join
            if context.scan(/<[a-zA-Z]/).size > context.scan(/<\/[a-zA-Z]/).size
              diagnostics << Diagnostic.new(
                filename, lineno, 1, :warning,
                "possible bare `#` comment inside tag body — may render as visible text. Use `<!-- comment -->` instead",
                line
              )
            end
          end
        end

        diagnostics
      end

      # ── Phase 2: Compilation check ───────────────────────────────
      # Try to compile the source and validate the output Ruby.
      def check_compilation(source, filename, mode)
        diagnostics = []

        begin
          compiled = if mode == :view
                       Grsx.compile(source)
                     else
                       Grsx::ExtendedParser.new(source).compile
                     end
        rescue => e
          diagnostics << Diagnostic.new(
            filename, extract_line(e), 1, :error,
            "RSX parse error: #{e.message.lines.first&.chomp}",
            nil
          )
          return diagnostics
        end

        # Validate the compiled Ruby is syntactically valid
        begin
          RubyVM::InstructionSequence.compile(compiled, filename)
        rescue SyntaxError => e
          line = extract_line(e)
          diagnostics << Diagnostic.new(
            filename, line, 1, :error,
            "compiled Ruby syntax error: #{e.message.lines.first&.chomp}",
            nil
          )
        end

        diagnostics
      end

      def extract_line(error)
        # Try to extract line number from error message
        if error.message =~ /:(\d+):/
          $1.to_i
        elsif error.message =~ /line (\d+)/i
          $1.to_i
        else
          1
        end
      end
    end
  end
end
