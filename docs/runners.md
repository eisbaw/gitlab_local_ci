# Runner fleet

`dry-run` schedules jobs on a mock fleet: one JSON file per runner in a
directory (`--runners DIR`, default `./runners`). Nothing connects to a real
runner. `run` and `export-just` do not use the fleet.

```json
{
  "id": "runner-1",
  "tags": ["docker", "linux"],
  "executor": "shell",
  "max_jobs": 2
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | String or integer, shown in the dry-run timeline. |
| `tags` (or `tag_list`) | yes | Array. A job runs here only if all its `tags:` are in this list. |
| `executor` | yes | String. Informational only. |
| `max_jobs` (or `concurrent`) | yes | Integer ≥ 1: jobs the runner takes at once. |
| `run_untagged` | no | `true` lets jobs without `tags:` run here. Default `false`. |

Other fields (`description`, `locked`, `access_level`, ...) are accepted and
ignored. A file that misses a required field, or is not valid JSON, stops the
dry-run with an error naming the file.

If no runner can take a job, dry-run stops as soon as that job is next to
run, lists the job and its tags, and exits 1. The fleet in `runners/` is an example; copy it next to your
project and edit the tags to match your real runners.
