# Test CI projects

Twenty `.gitlab-ci.yml` fixtures, from a single job to a large mixed
pipeline, each exercising one area of GitLab CI. They are parsed and
simulated, never executed: features such as services, artifacts or cache are
checked as configuration, not run. Some projects include other files (proj11,
proj16, proj20), and each has a small `justfile`.

| Project | Exercises | Project | Exercises |
|---|---|---|---|
| proj1 | minimal config | proj11 | `include:` |
| proj2 | multiple stages | proj12 | YAML anchors |
| proj3 | parallel jobs | proj13 | `extends:` |
| proj4 | `needs:` DAG | proj14 | retry / timeout |
| proj5 | variables | proj15 | reports / coverage |
| proj6 | artifacts | proj16 | child pipelines |
| proj7 | services | proj17 | `parallel:matrix` |
| proj8 | rules | proj18 | resource groups |
| proj9 | cache | proj19 | complex DAG |
| proj10 | `before_script` / `after_script` | proj20 | everything at once |

`projN.output_reference/` holds the expected lint, dag and dry-run output;
`just e2e` (repo root) checks every project against it. Current job counts:

```bash
grep -H '^Jobs:' test_ci_projects/*.output_reference/lint.txt
```

See [TESTING.md](TESTING.md) for the recipes and the golden workflow, and
[docs/development.md](../docs/development.md) for the gates.
