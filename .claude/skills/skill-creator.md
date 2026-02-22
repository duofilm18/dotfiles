---
name: skill-creator
description: >
  Guide for creating effective skills. Use when creating a new skill or updating an existing
  skill that extends Claude's capabilities with specialized knowledge, workflows, or tool
  integrations.
---

# Skill Creator

This skill provides guidance for creating effective skills.

## Core Principles

### Concise is Key

The context window is a public good. Only add context Claude doesn't already have.
Prefer concise examples over verbose explanations.

### Set Appropriate Degrees of Freedom

- **High freedom (text instructions)**: Multiple valid approaches
- **Medium freedom (pseudocode/scripts)**: Preferred pattern exists
- **Low freedom (specific scripts)**: Operations are fragile, consistency critical

### Anatomy of a Skill

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter metadata (required)
│   │   ├── name: (required)
│   │   ├── description: (required)
│   │   └── compatibility: (optional, rarely needed)
│   └── Markdown instructions (required)
└── Bundled Resources (optional)
    ├── scripts/       - Executable code (Python/Bash/etc.)
    ├── references/    - Documentation loaded into context as needed
    └── assets/        - Files used in output (templates, icons, fonts, etc.)
```

### SKILL.md

- **Frontmatter (YAML)**: `name` and `description` are required. `description` is the primary
  triggering mechanism — include both what the skill does AND when to use it. The body is only
  loaded after triggering.
- **Body (Markdown)**: Instructions and guidance. Use imperative/infinitive form. Keep under
  500 lines. Split into separate reference files when approaching this limit.

### Progressive Disclosure

1. **Metadata (name + description)** — Always in context (~100 words)
2. **SKILL.md body** — When skill triggers (<5k words)
3. **Bundled resources** — As needed (unlimited)

### What NOT to Include

Do NOT create extraneous files: README.md, INSTALLATION_GUIDE.md, CHANGELOG.md, etc.
Only include information needed for Claude to do the job.

## Skill Creation Process

1. **Understand** the skill with concrete examples
2. **Plan** reusable contents (scripts, references, assets)
3. **Initialize** the skill directory
4. **Edit** — implement resources, write SKILL.md
5. **Iterate** based on real usage

### Frontmatter Guidelines

```yaml
---
name: my-skill-name
description: >
  What the skill does and specific triggers/contexts for when to use it.
  Include all "when to use" information here, not in the body.
---
```

### Body Guidelines

- Use imperative/infinitive form
- Keep under 500 lines
- Split detailed information into `references/` files
- Reference those files clearly from SKILL.md with guidance on when to read them
- Avoid deeply nested references — keep one level deep from SKILL.md
- For files >100 lines, include a table of contents

### Bundled Resources

| Type | Purpose | When to include |
|------|---------|-----------------|
| `scripts/` | Executable code | Same code rewritten repeatedly or deterministic reliability needed |
| `references/` | Documentation for context | Detailed schemas, API docs, domain knowledge |
| `assets/` | Files used in output | Templates, images, boilerplate that get copied/modified |
