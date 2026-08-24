# Setting up the self-hosted scrape runner on CachyOS

This is a handoff doc for registering a GitHub Actions self-hosted runner on the
CachyOS machine so `.github/workflows/scrape.yml` scrapes from a residential IP
(fixing the Cloudflare 403s documented in `docs/test-plan.md` §2/§9) instead of
a manually-triggered local run.

The workflow only triggers on `schedule`/`workflow_dispatch` (never
`pull_request`), so a fork PR can never get code executed on this runner
without a maintainer manually approving and running it there — keep it that
way in any future workflow that targets this runner.

## 1. Install Docker

```sh
sudo pacman -S --needed docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Log out and back in (or run `newgrp docker`) so your shell picks up the new
group membership. Verify with `docker run hello-world`.

## 2. Register the runner

1. On GitHub: `https://github.com/mehedibangladeshi/newshead` → **Settings →
   Actions → Runners → New self-hosted runner** → OS: Linux, Arch: x64.
2. Create a dedicated directory for this repo's runner — keep it separate
   from any other repo's runner on the same box (e.g. the `DailyNewspaperPublish`
   runner, if that's registered here too):
   ```sh
   mkdir -p ~/actions-runners/newshead && cd ~/actions-runners/newshead
   ```
3. Run the download + `./config.sh --url ... --token ...` commands GitHub
   generates on that Runners page (the token is single-use and expires
   quickly, so copy it fresh from the page rather than reusing an old one).
   Accept the default labels — no custom label is needed; `[self-hosted, Linux]`
   in `scrape.yml` is already satisfied by a runner's default labels.

## 3. Install as a systemd service

So it survives reboots and starts automatically:

```sh
sudo ./svc.sh install
sudo ./svc.sh start
```

Verify:

```sh
sudo systemctl status 'actions.runner.mehedibangladeshi-newshead.*'
```

## 4. Confirm the service user can run Docker

Systemd services don't automatically pick up a group added via `usermod` to
an already-running session — if `docker build`/`docker run` fail with a
permission error in the workflow log, restart the service (and/or reboot the
box) after confirming group membership:

```sh
groups "$USER"   # should list "docker"
sudo systemctl restart 'actions.runner.mehedibangladeshi-newshead.*'
```

## 5. First test run

From any machine with `gh` configured:

```sh
gh workflow run scrape.yml
```

On the CachyOS box, watch the runner pick up the job:

```sh
sudo journalctl -u 'actions.runner.*newshead*' -f
```

And check the GitHub Actions tab / job log for all 8 sources logging
`collected N article(s)` with none of the 5 previously-blocked sources
(jugantor, dhakatribune, ittefaq, banglatribune, samakal) returning 0.

## 6. Maintenance

- The runner binary self-updates automatically — no action needed.
- CachyOS's rolling-release `pacman -Syu` will occasionally update Docker.
  If the runner service fails to pick up a job after a system update:
  ```sh
  sudo systemctl restart docker
  sudo ./svc.sh start   # from ~/actions-runners/newshead
  ```
- If the box is offline or the service is down, `.github/workflows/scrape-fallback.yml`
  picks up the schedule 2 hours later on a GitHub-hosted runner — it'll only
  pull the 3 sources that work from a GitHub IP, but keeps the feed from
  going fully stale until the runner is back.
