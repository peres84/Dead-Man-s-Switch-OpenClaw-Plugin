import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { exec } from "node:child_process";
import { promisify } from "node:util";
import { readFile, appendFile, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const execAsync = promisify(exec);

const FIX_LOG_PATH = join(homedir(), ".openclaw", "dms-fix-log.jsonl");
const SCRIPTS_DIR = "/usr/local/bin/openclaw-skills";

interface FixLogEntry {
  timestamp: string;
  service: string;
  issue: string;
  fix: string;
  result: "success" | "failure";
  duration_ms: number;
}

async function ensureLogDir(): Promise<void> {
  await mkdir(join(homedir(), ".openclaw"), { recursive: true });
}

async function appendFixLog(entry: FixLogEntry): Promise<void> {
  await ensureLogDir();
  await appendFile(FIX_LOG_PATH, JSON.stringify(entry) + "\n", "utf-8");
}

async function readFixLog(): Promise<FixLogEntry[]> {
  try {
    const content = await readFile(FIX_LOG_PATH, "utf-8");
    return content
      .trim()
      .split("\n")
      .filter((line) => line.trim())
      .map((line) => JSON.parse(line) as FixLogEntry);
  } catch {
    return [];
  }
}

function countRecentOccurrences(
  entries: FixLogEntry[],
  service: string,
  withinMs: number
): number {
  const cutoff = Date.now() - withinMs;
  return entries.filter(
    (e) =>
      e.service === service && new Date(e.timestamp).getTime() >= cutoff
  ).length;
}

export default definePluginEntry({
  id: "deadmans-switch",
  name: "Dead Man's Switch",
  description: "Self-healing infrastructure guardian",
  register(api) {
    // Tool: execute a recovery script
    api.registerTool({
      name: "dms_recover",
      description:
        "Execute a Dead Man's Switch recovery script for a named service. " +
        "Runs the appropriate privileged script, logs the result, and returns output.",
      parameters: Type.Object({
        service: Type.String({
          description:
            "Service name to recover: tailscale | nginx | disk | process",
        }),
        reason: Type.String({
          description: "Why recovery is being triggered",
        }),
        processName: Type.Optional(
          Type.String({
            description:
              "For service=process: the systemd service name to restart",
          })
        ),
      }),
      async execute(_id, params) {
        const { service, reason, processName } = params;
        const start = Date.now();

        let scriptPath: string;
        let scriptArgs = "";

        switch (service) {
          case "tailscale":
            scriptPath = `${SCRIPTS_DIR}/tailscale-funnel-start.sh`;
            break;
          case "nginx":
            scriptPath = `${SCRIPTS_DIR}/nginx-check.sh`;
            break;
          case "disk":
            scriptPath = `${SCRIPTS_DIR}/disk-cleanup.sh`;
            break;
          case "process":
            scriptPath = `${SCRIPTS_DIR}/process-restart.sh`;
            scriptArgs = processName ? ` ${processName}` : "";
            break;
          default:
            return {
              success: false,
              error: `Unknown service: ${service}. Valid values: tailscale, nginx, disk, process`,
            };
        }

        let stdout = "";
        let stderr = "";
        let result: "success" | "failure" = "success";

        try {
          const output = await execAsync(
            `sudo ${scriptPath}${scriptArgs}`,
            { timeout: 120_000 }
          );
          stdout = output.stdout;
          stderr = output.stderr;
        } catch (err: unknown) {
          result = "failure";
          const execErr = err as { stdout?: string; stderr?: string; message?: string };
          stdout = execErr.stdout ?? "";
          stderr = execErr.stderr ?? execErr.message ?? String(err);
        }

        const duration_ms = Date.now() - start;
        const entry: FixLogEntry = {
          timestamp: new Date().toISOString(),
          service,
          issue: reason,
          fix: `ran ${scriptPath}${scriptArgs}`,
          result,
          duration_ms,
        };

        await appendFixLog(entry);

        // Check if we should suggest a cron (2+ occurrences in last 24h)
        const allEntries = await readFixLog();
        const recentCount = countRecentOccurrences(
          allEntries,
          service,
          24 * 60 * 60 * 1000
        );
        const suggestCron = recentCount >= 2;

        const cronCommand =
          suggestCron
            ? `openclaw cron add --name "DMS: ${service} Monitor" --cron "*/5 * * * *" --session isolated --message "Dead Man's Switch: check ${service}. If issue found, fix it." --announce`
            : null;

        return {
          success: result === "success",
          service,
          duration_ms,
          stdout: stdout.trim(),
          stderr: stderr.trim() || undefined,
          logged: true,
          recentOccurrences: recentCount,
          suggestCron,
          cronCommand,
          message:
            result === "success"
              ? `Recovery successful for ${service} (${duration_ms}ms)${suggestCron ? ` — this has failed ${recentCount} times in 24h, consider setting up cron monitoring` : ""}`
              : `Recovery FAILED for ${service} after ${duration_ms}ms — manual intervention may be needed`,
        };
      },
    });

    // Tool: get fix log summary
    api.registerTool({
      name: "dms_status",
      description:
        "Get Dead Man's Switch fix log — recent incidents and recovery history. " +
        "Returns the last 20 entries with summary statistics.",
      parameters: Type.Object({}),
      async execute(_id, _params) {
        const entries = await readFixLog();
        const last20 = entries.slice(-20);

        const now = Date.now();
        const last24h = entries.filter(
          (e) => now - new Date(e.timestamp).getTime() < 24 * 60 * 60 * 1000
        );

        // Count by service in last 24h
        const serviceCounts: Record<string, number> = {};
        for (const e of last24h) {
          serviceCounts[e.service] = (serviceCounts[e.service] ?? 0) + 1;
        }

        const recurringServices = Object.entries(serviceCounts)
          .filter(([, count]) => count >= 2)
          .map(([service, count]) => ({ service, count }));

        return {
          totalIncidents: entries.length,
          last24hIncidents: last24h.length,
          recurringServices,
          last20Entries: last20,
          logPath: FIX_LOG_PATH,
          message:
            entries.length === 0
              ? "No incidents recorded yet."
              : `${entries.length} total incidents. ${last24h.length} in last 24h.${recurringServices.length > 0 ? ` Recurring: ${recurringServices.map((s) => `${s.service} (${s.count}x)`).join(", ")}` : ""}`,
        };
      },
    });

    // Hook: on gateway startup, check fix log for recurring patterns
    api.registerHook(["gateway:startup"], async (event) => {
      let entries: FixLogEntry[];
      try {
        entries = await readFixLog();
      } catch {
        return;
      }

      if (entries.length === 0) return;

      const now = Date.now();
      const last24h = entries.filter(
        (e) => now - new Date(e.timestamp).getTime() < 24 * 60 * 60 * 1000
      );

      const serviceCounts: Record<string, number> = {};
      for (const e of last24h) {
        serviceCounts[e.service] = (serviceCounts[e.service] ?? 0) + 1;
      }

      const recurringServices = Object.entries(serviceCounts).filter(
        ([, count]) => count >= 2
      );

      if (recurringServices.length === 0) return;

      const messages = recurringServices.map(([service, count]) => {
        const cronCommand = `openclaw cron add --name "DMS: ${service} Monitor" --cron "*/5 * * * *" --session isolated --message "Dead Man's Switch: check ${service}. If issue found, fix it using the appropriate playbook." --announce`;
        return `⚠️  Dead Man's Switch detected recurring failure: **${service}** failed ${count} times in the last 24h.\n\nRun this to set up automatic monitoring:\n\`\`\`\n${cronCommand}\n\`\`\``;
      });

      // Post a message to the gateway chat so the user sees the alert on startup
      if (typeof event?.messages?.push === "function") {
        for (const msg of messages) {
          event.messages.push({ role: "assistant", content: msg });
        }
      }
    });
  },
});
