# CLAUDE.md

## Commit messages

Always follow this pattern for commit message lines:

```
<task_type>(<location/feature/module name>): <task description in ~80 characters>
```

- `task_type`: e.g. `fix`, `feat`, `chore`, `docs`, `refactor`.
- `location/feature/module name`: the file, widget, screen, or feature the change touches (e.g. `home_screen`, `news_card`, `article_repository`).
- A single commit may contain multiple tasks — add one line per task, each following the pattern above.
- Never add `Co-Authored-By: Claude` or any similar AI-attribution line to commits.
