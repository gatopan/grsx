# GRSX for VSCode

This extension provides syntax highlighting and language support for GRSX (Ruby + HTML templating) inside Visual Studio Code.

## Features
- First-class syntax highlighting for `.rsx` and `.html.rsx` files.
- Highlights HTML/JSX-style tags perfectly intermixed within Ruby context.
- Full support for interpolated Ruby expressions closures: `href={<ruby_code>}`.
- Autoclosing tags and smart bracket matching.

## Local Installation

This extension is built directly into the GRSX repository. To install it locally for development:

```bash
# From the GRSX repository root
cd editors/vscode

# Package with VSCE and install
npx @vscode/vsce package
agy --install-extension grsx-0.1.0.vsix
```

## How It Works
The `source.rsx` language grammar builds entirely upon VSCode's built-in `source.ruby` grammar, injecting rules for matching `<tag>` tokens, and safely passing over `{...}` embedded expressions back to Ruby parsing. This provides the most faithful representation of GRSX's behavior.
