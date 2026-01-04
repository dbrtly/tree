# General Code Style Principles

This document outlines general coding principles that apply across all languages and frameworks used in this project.

## Readability
- Code should be easy to read and understand by humans.
- Avoid overly clever or obscure constructs.

## Consistency
- Follow existing patterns in the codebase.
- Maintain consistent formatting, naming, and structure.
- run `zig build fmt` to format the code.

## Simplicity
- Prefer simple solutions over complex ones.
- Break down complex problems into smaller, manageable parts.

## Maintainability
- Write code that is easy to test, modify and extend.
- Minimize dependencies and coupling.
- run `zig build ci` to check for maintainability violations.

## Documentation
- Document *why* something is done, not just *what*.
- Keep documentation up-to-date with code changes.
