import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const FIX_LOG_PATH = join(homedir(), ".openclaw", "dms-fix-log.jsonl");

interface FixLogEntry {
  timestamp: string;
  service: string;
  issue: string;
  fix: string;
  result: "success" | "failure";
  duration_ms: number;
}

interface GatewayStartupEvent {
  messages?: Array<{ role: string; content: string }>;
  [key: string]: unknown;
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

export async function handler(event: GatewayStartupEvent): Promise<void> {
  const entries = await readFixLog();
  if (entries.length === 0) return;

  const now = Date.now();
  const oneDayMs = 24 * 60 * 60 * 1000;

  const recent = entries.filter(
    (e) => now - new Date(e.timestamp).getTime() < oneDayMs
  );

  if (recent.length === 0) return;

  // Count occurrences per service in last 24h
  const serviceCounts = new Map<string, number>();
  for (const entry of recent) {
    serviceCounts.set(entry.service, (serviceCounts.get(entry.service) ?? 0) + 1);
  }

  const recurring = [...serviceCounts.entries()].filter(([, count]) => count >= 2);
  if (recurring.length === 0) return;

  const messages: string[] = [];

  for (const [service, count] of recurring) {
    const lastEntry = [...recent].reverse().find((e) => e.service === service);
    const lastResult = lastEntry?.result ?? "unknown";
    const lastIssue = lastEntry?.issue ?? "unknown issue";

    const cronMessage = buildCronMessage(service);
    const cronCommand = buildCronCommand(service);

    messages.push(
      `⚠️  **Dead Man's Switch Alert**\n\n` +
      `\`${service}\` has failed **${count} times** in the last 24 hours.\n` +
      `Last incident: *${lastIssue}* (${lastResult})\n\n` +
      `To set up automatic monitoring every 5 minutes, run:\n` +
      `\`\`\`bash\n${cronCommand}\n\`\`\``
    );

    void cronMessage; // referenced for completeness
  }

  // Post messages to gateway chat on startup
  if (Array.isArray(event.messages)) {
    for (const msg of messages) {
      event.messages.push({ role: "assistant", content: msg });
    }
  }
}

function buildCronCommand(service: string): string {
  const cronMsg = buildCronMessage(service);
  return (
    `openclaw cron add ` +
    `--name "DMS: ${capitalize(service)} Monitor" ` +
    `--cron "*/5 * * * *" ` +
    `--session isolated ` +
    `--message "${cronMsg.replace(/"/g, '\\"')}" ` +
    `--announce`
  );
}

function buildCronMessage(service: string): string {
  switch (service) {
    case "tailscale":
      return (
        "Dead Man's Switch: Check tailscale funnel status. " +
        "Run: tailscale funnel status. " +
        "If output contains (tailnet only), run: sudo /usr/local/bin/tailscale-funnel-start.sh, " +
        "then verify and log result to ~/.openclaw/dms-fix-log.jsonl."
      );
    case "nginx":
      return (
        "Dead Man's Switch: Check website health. " +
        "Check Tailscale first (tailscale funnel status). " +
        "Then curl -sI each configured website in config.websites. " +
        "If non-200, diagnose and fix using nginx playbook."
      );
    case "disk":
      return (
        "Dead Man's Switch: Check disk usage with df -h /. " +
        "If above 85%, run disk cleanup: apt-get clean, journalctl vacuum, and remove old logs."
      );
    default:
      return (
        `Dead Man's Switch: Check if ${service} service is running. ` +
        `Run: sudo systemctl status ${service}. ` +
        `If not running, restart it and log the result.`
      );
  }
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
