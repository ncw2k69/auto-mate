# 🤖 Auto-Mate - Lightweight Bash Automation Framework

A **lightweight, portable bash automation framework** designed for low-resource computers such as the Raspberry Pi Zero 2, Intel Atom boards, and any Debian-based Linux system. Orchestrates external processes (vite, bun, python) through a clean folder-based structure - no daemons, no heavy runtimes, no configuration files.



## The WHY?

Most automation and task scheduling solutions (Celery, Airflow, n8n, etc.) are built for servers with ample CPU and RAM. When you need reliable, repeating task execution on edge hardware with 512 MB of RAM and a single-core CPU, those tools become the problem instead of the solution.

This framework was built around a single idea: **a cron tick is all the scheduler you need**. Everything else - parallelism, sequencing, lock management, progress tracking, and log rotation - is handled by plain bash scripts with zero external dependencies.



## How It Works

Every minute (or at your chosen interval), `automation.sh` is triggered by cron or systemd. It delegates work to two independent orchestrators:

| Orchestrator  | Folder      | Behavior                                                        |
| ------------- | ----------- | --------------------------------------------------------------- |
| `serial.sh`   | `series/`   | Runs each project's scripts **in order**, one after another     |
| `parallel.sh` | `parallel/` | Fires each project's scripts **independently**, fire-and-forget |

Both orchestrators run **concurrently** with each other. Within each orchestrator, all **projects** also run concurrently. The difference is at the script level: serial projects enforce ordering, parallel projects do not.



## Framework Structure

```
automation/
├── automation.sh             ← Main entry point (cron / systemd trigger)
├── startup.sh                ← Boot-time script: clears locks then triggers first run
├── serial.sh                 ← Serial folder orchestrator
├── parallel.sh               ← Parallel folder orchestrator
├── stats.sh                  ← Colored live status reporter
├── monitor.sh                ← watch(1) wrapper for stats.sh
├── process.stop              ← create this file to pause everything
├── templates/
│   └── template-parallel.sh  ← Starter template for parallel scripts
├── logs/                     ← Daily log files (auto-pruned after 15 days)
│   └── YYYY-MM-DD.log
├── series/                   ← Serial project folders live here
│   ├── project-a/
│   │   ├── 01-fetch.sh
│   │   ├── 02-process.sh
│   │   ├── 03-report.sh
│   │   ├── .lock             ← Created by serial.sh, auto-removed on finish
│   │   └── .progress.status  ← Written and updated by serial.sh
│   └── project-b/
│       └── ...
└── parallel/                 ← Parallel project folders live here
    ├── project-a/
    │   ├── analyze.sh
    │   ├── analyze.sh.lock   ← Created/removed by the script itself
    │   └── fetch.sh
    └── project-b/
        └── ...
```



## Series vs Parallel - In Detail

### Series Projects (`series/`)

Scripts inside a series project folder are **executed in ascending filename order**, one after another. The project will not start again until the previous run finishes (enforced by a `.lock` file).

**Progress tracking** - `.progress.status` contains three lines at all times:
```
40%            ← completion percentage
02-process.sh  ← currently running script
01-fetch.sh    ← previously completed script (or "started..." if none yet)
```
When all scripts complete, the file is replaced with a single line: `done`.  
If a script fails, the file contains `error` and execution stops for that project until the next cron trigger.

**Script naming tip:** prefix scripts with numbers to control execution order:
```
01-fetch-data.sh
02-transform.sh
03-upload-results.sh
```

### Parallel Projects (`parallel/`)

Scripts inside a parallel project are **fired independently** - the orchestrator does not wait for any of them to finish. Each script manages its own `.lock` file (created at start, removed at finish or crash) using `template-parallel.sh`.

If a script's lock file is present when the orchestrator runs, that script is skipped for that tick, preventing overlapping executions of the same script.



## Process Kill-Switch

To **immediately halt** all future automation triggers without touching cron or systemd:

```bash
touch /path/to/automation/process.stop
```

Every subsequent cron tick will detect this file and exit without running anything. Currently-running scripts are **not killed** - they finish naturally.

To **resume** automation:

```bash
rm /path/to/automation/process.stop
```

The next cron tick will run as normal.



## Clearing Locks Manually

Lock files protect against overlapping runs, but after a crash or forced kill they can be left on disk and block the next execution. The `--clear-locks` flags let you wipe them without manually hunting through project folders.

| Command                                 | Effect                                                                |
| --------------------------------------- | --------------------------------------------------------------------- |
| `./automation.sh --clear-locks`         | Clears all locks and status files from both `series/` and `parallel/` |
| `./automation.sh --clear-lock=series`   | Clears `.lock` and `.progress.status` from all series project folders |
| `./automation.sh --clear-lock=parallel` | Clears all `*.sh.lock` files from all parallel project folders        |

**Example - after a hard reboot left locks behind:**

```bash
./automation.sh --clear-locks
```

```
[2026-04-15 09:00:01] [INFO ] [automation] === Clear-locks requested (series + parallel) ===
[2026-04-15 09:00:01] [INFO ] [automation] Clearing series locks and status files...
[2026-04-15 09:00:01] [INFO ] [automation]   [series/project-a] Removed .lock
[2026-04-15 09:00:01] [INFO ] [automation]   [series/project-a] Removed .progress.status
[2026-04-15 09:00:01] [INFO ] [automation] Clearing parallel lock files...
[2026-04-15 09:00:01] [INFO ] [automation]   Removed parallel/project-b/analyze.sh.lock
[2026-04-15 09:00:01] [INFO ] [automation] === Clear-locks complete ===
```

> These flags are also called automatically by `startup.sh` on every system boot - you rarely need to run them by hand.



## Creating a Serial Project

1. Create a folder inside `series/`:
   ```bash
   mkdir series/my-project
   ```

2. Add your `.sh` scripts, named in the order you want them to run:
   ```bash
   touch series/my-project/01-step-one.sh
   touch series/my-project/02-step-two.sh
   ```

3. Inside each script, call your Python or Bun process:
   ```bash
   #!/usr/bin/env bash
   python3 "$(dirname "$(realpath "$0")")/my_script.py"
   ```

4. Make them executable (or let the framework do it automatically):
   ```bash
   chmod +x series/my-project/*.sh
   ```

> If any script exits with a non-zero code, the project stops and waits for the next trigger. Check the daily log file for details.



## Creating a Parallel Project

1. Create a folder inside `parallel/`:
   ```bash
   mkdir parallel/my-project
   ```

2. Copy the template for each script you want to add:
   ```bash
   cp templates/template-parallel.sh parallel/my-project/analyze.sh
   cp templates/template-parallel.sh parallel/my-project/fetch-data.sh
   ```

3. Edit each script and add your Python or Bun calls in the marked section:
   ```bash
   # ── YOUR CODE BELOW ──────────────────────────────────────────────
   python3 "$(dirname "$(realpath "$0")")/analyze.py"
   # or
   bun run "$(dirname "$(realpath "$0")")/analyze.js"
   ```

4. That's it. The template handles lock creation, lock removal, and crash recovery automatically.



## Monitoring Status

### Live monitor (recommended)

```bash
# Default: refresh every 5 seconds
./monitor.sh

# Custom interval (e.g. every 2 seconds)
./monitor.sh 2
```

### One-shot status

```bash
./stats.sh
```

**Example output:**

```
🤖 Auto-Mate Monitor • 2026-04-20 03:14:06

SERIES
  blank    (no scripts)
  deploy   d-build   80%
  stats    done

PARALLEL
  none   (no scripts)
  one-shot   backup-logs   working
  online-shop
    ├─ process-orders     idle
    ├─ process-payments   working
    └─ send-newsletter    idle
  promos
    ├─ build-campaigns     working
    └─ update-email-list   idle

```

| Status    | Meaning                                  |
| --------- | ---------------------------------------- |
| `idle`    | Not running, waiting for next trigger    |
| `working` | Currently executing (parallel)           |
| `40%`     | In progress at 40% (serial)              |
| `done`    | Last run completed successfully          |
| `error`   | Last run stopped due to a script failure |



## Setup Guide

### Step 1 - Clone the repository

```bash
git clone https://github.com/ncw2k69/auto-mate.git
cd auto-mate
```

### Step 2 - Make all scripts executable

```bash
chmod +x *.sh templates/*.sh
```

### Step 3 - Test a dry run

```bash
bash automation.sh
```

Check the `logs/` folder for today's log file. If `series/` and `parallel/` are empty, you will see `no projects found` - that is expected.

### Step 4a - Schedule with Cron

Open the crontab editor:

```bash
crontab -e
```

Add the following line to run every minute:

```cron
* * * * * /bin/bash /absolute/path/to/automation/automation.sh
```


**(OR)** To run every 5 minutes instead:

```cron
*/5 * * * * /bin/bash /absolute/path/to/automation/automation.sh
```

Verify the cron entry is registered:

```bash
crontab -l
```

### Step 4b - Schedule with systemd (alternative)

Create a service unit file:

```bash
sudo nano /etc/systemd/system/automation.service
```

```ini
[Unit]
Description=Automation Framework
After=network.target

[Service]
Type=oneshot
User=YOUR_USERNAME
ExecStart=/bin/bash /absolute/path/to/automation/automation.sh
StandardOutput=null
StandardError=null
```

Create a timer unit file:

```bash
sudo nano /etc/systemd/system/automation.timer
```

```ini
[Unit]
Description=Automation Framework Timer
Requires=automation.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=1s

[Install]
WantedBy=timers.target
```

Enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable automation.timer
sudo systemctl start automation.timer
```

Verify the timer is active:

```bash
systemctl status automation.timer
systemctl list-timers automation.timer
```

To check execution logs:

```bash
journalctl -u automation.service -f
```

### Step 4c - Startup service (clears locks on boot)

`startup.sh` runs once at boot, before the regular timer begins. It clears any stale lock files left over from the previous session (power loss, crash, forced shutdown), then fires an immediate first run so you don't wait up to 1 minute for the first cron tick.

Create a dedicated oneshot service:

```bash
sudo nano /etc/systemd/system/automation-startup.service
```

```ini
[Unit]
Description=Automation Framework - Startup (lock cleanup + first run)
# Must complete before the repeating timer starts
Before=automation.timer
After=network.target

[Service]
Type=oneshot
User=YOUR_USERNAME
ExecStart=/bin/bash /absolute/path/to/automation/startup.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable automation-startup.service
```

> The service is `Type=oneshot` with `RemainAfterExit=yes`, so systemd considers it "active" after it finishes. The `Before=automation.timer` ordering ensures it always runs first on boot.

To view its output after a reboot:

```bash
journalctl -u automation-startup.service
```

### Step 5 - Create your first project

**Serial example:**

```bash
mkdir series/hello-world
cat > series/hello-world/01-say-hello.sh << 'EOF'
#!/usr/bin/env bash
echo "Hello from serial project"
python3 "$(dirname "$(realpath "$0")")/hello.py"
EOF
chmod +x series/hello-world/01-say-hello.sh
```

**Parallel example:**

```bash
mkdir parallel/hello-world
cp templates/template-parallel.sh parallel/hello-world/my-task.sh
# Edit parallel/hello-world/my-task.sh and add your python/bun call
```

### Step 6 - Monitor execution

```bash
./monitor.sh
```



## Log Files

Log files are stored in `logs/` as `YYYY-MM-DD.log` and are automatically deleted after **15 days** (configurable via `LOG_RETENTION_DAYS` in `automation.sh`).

**Log format:**
```
[2026-04-15 14:23:01] [INFO ] [serial]   [project-a] Starting execution of 3 script(s)
[2026-04-15 14:23:04] [INFO ] [serial]   [project-a] Completed: 01-fetch.sh (exit 0)
[2026-04-15 14:23:10] [ERROR] [serial]   [project-a] 02-process.sh failed with exit code 1
[2026-04-15 14:23:01] [INFO ] [parallel] [project-b] Skipping fetch.sh - lock file present
```

To tail the current day's log:

```bash
tail -f logs/$(date '+%Y-%m-%d').log
```



## Challenges & Solutions

### Stale locks after power loss or forced reboot
**Problem:** A hard shutdown (power cut, `kill -9`) leaves `.lock` and `*.sh.lock` files on disk. The next cron tick skips those projects entirely, silently doing nothing until someone manually removes the files.  
**Solution:** `startup.sh` runs `automation.sh --clear-locks` as a systemd oneshot service on every boot, before the timer starts. All stale locks are swept away automatically - no manual intervention needed.

### Atomic lock file creation
**Problem:** Two cron triggers arriving within milliseconds could both pass the "no lock" check and create a race condition.  
**Solution:** `( set -C; echo $$ > .lock ) 2>/dev/null` - bash's noclobber mode (`set -C`) makes file creation atomic at the OS level. Only one process wins; the other detects failure and skips.

### Stale lock files after crashes
**Problem:** If a script is killed (SIGKILL, power loss), lock files may remain and permanently block future runs.  
**Solution (parallel):** `trap 'rm -f "$LOCK_FILE"' EXIT` catches normal exits, errors, and most signals - but not SIGKILL. Manual removal: `rm parallel/my-project/my-script.sh.lock`.  
**Solution (serial):** Same trap strategy on the project subshell. Manual removal: `rm series/my-project/.lock`.

### Low-resource parallel execution
**Problem:** Spawning too many processes simultaneously on 512 MB RAM hardware.  
**Solution:** The framework itself is extremely lean (bash subshells, no forks beyond the scripts you define). You control the load by how many projects and scripts you create. Serial projects naturally throttle resource usage through sequential execution.

### Log file growth
**Problem:** Logs accumulate indefinitely on low-storage devices.  
**Solution:** `find logs/ -name "*.log" -mtime +15 -delete` runs on every trigger. The retention period is a single variable (`LOG_RETENTION_DAYS`) at the top of `automation.sh`.



## File Reference

| File                                  | Purpose                                                                                                  |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `automation.sh`                       | Main entry point. Checks kill-switch, prunes logs, launches orchestrators. Accepts `--clear-locks` flags |
| `startup.sh`                          | Boot-time script. Clears all stale locks then triggers the first automation run                          |
| `serial.sh`                           | Runs series project scripts sequentially, projects in parallel                                           |
| `parallel.sh`                         | Fires parallel project scripts independently (fire-and-forget)                                           |
| `stats.sh`                            | Colored terminal status for all projects                                                                 |
| `monitor.sh`                          | `watch` wrapper for `stats.sh`                                                                           |
| `templates/template-parallel.sh`      | User template for parallel scripts (handles lock lifecycle)                                              |
| `process.stop`                        | Create this file to halt automation; delete to resume                                                    |
| `logs/YYYY-MM-DD.log`                 | Daily log file, auto-pruned after 15 days                                                                |
| `series/<project>/.lock`              | Indicates a serial project is currently running                                                          |
| `series/<project>/.progress.status`   | Live progress of the running serial project                                                              |
| `parallel/<project>/<script>.sh.lock` | Indicates a parallel script is currently running                                                         |


